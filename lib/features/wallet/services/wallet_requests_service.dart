import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:giggre_app/main.dart' show flavor;

// Gig Wallet requests (functions/src/walletRequests.ts): Top Up with manual
// proof and Send to another user, both approved by a Giggre admin. The app
// never writes a balance — it only calls these callables and reads.

final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

double? _amount(Object? v) =>
    v is num && v > 0 ? (v * 100).round() / 100 : null;

class WalletRequestException implements Exception {
  final String message;
  const WalletRequestException(this.message);
  @override
  String toString() => message;
}

class WalletAmountLimits {
  final bool enabled;
  final double? min;
  final double? max;
  final double? dailyMax;
  const WalletAmountLimits({
    required this.enabled,
    this.min,
    this.max,
    this.dailyMax,
  });
  static const closed = WalletAmountLimits(enabled: false);
}

/// How a manual top up is paid (set per method in giggre-admin →
/// Gig Wallet → Settings).
enum DepositKind {
  /// GCash / Maya / bank transfer: accountName + accountNumber.
  ewallet,

  /// Cash at a Giggre office: accountName = office, accountNumber = address,
  /// details = hours. Proof = official receipt number.
  office,

  /// Remittance center: accountName = receiver, accountNumber = receiver
  /// mobile, details = address / accepted centers. Proof = control number.
  remittance;

  static DepositKind parse(Object? v) => switch (v) {
    'office' => DepositKind.office,
    'remittance' => DepositKind.remittance,
    _ => DepositKind.ewallet,
  };

  /// What the proof number is called.
  String get referenceLabel => switch (this) {
    DepositKind.ewallet => 'reference number',
    DepositKind.office => 'official receipt (OR) number',
    DepositKind.remittance => 'control / tracking number',
  };
}

class DepositAccount {
  final DepositKind kind;
  final String method;
  final String accountName;
  final String accountNumber;
  final String details;
  const DepositAccount(
    this.method,
    this.accountName,
    this.accountNumber, {
    this.kind = DepositKind.ewallet,
    this.details = '',
  });
}

/// general_config/wallet_requests — missing doc = closed. Limits are in USD;
/// convert with FxRates before showing them to a PHP user.
class WalletRequestConfig {
  final bool enabled;
  final WalletAmountLimits deposit;
  final WalletAmountLimits transfer;
  final List<DepositAccount> depositAccounts;
  final String depositNote;

  const WalletRequestConfig({
    required this.enabled,
    required this.deposit,
    required this.transfer,
    this.depositAccounts = const [],
    this.depositNote = '',
  });

  static const closed = WalletRequestConfig(
    enabled: false,
    deposit: WalletAmountLimits.closed,
    transfer: WalletAmountLimits.closed,
  );

  bool get canTopUp => enabled && deposit.enabled;

  List<DepositAccount> accountsOf(DepositKind kind, {String? method}) =>
      depositAccounts
          .where((a) =>
              a.kind == kind &&
              (method == null || a.method.toLowerCase() == method.toLowerCase()))
          .toList();
  bool get canSend => enabled && transfer.enabled;

  factory WalletRequestConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return closed;
    WalletAmountLimits lim(Object? raw) {
      final m = raw is Map ? raw : const {};
      return WalletAmountLimits(
        enabled: m['enabled'] == true,
        min: _amount(m['min']),
        max: _amount(m['max']),
        dailyMax: _amount(m['dailyMax']),
      );
    }

    final accounts = <DepositAccount>[];
    final raw = d['depositAccounts'];
    if (raw is List) {
      for (final a in raw) {
        if (a is Map) {
          final m = a['method'], n = a['accountName'], no = a['accountNumber'];
          if (m is String && n is String && no is String) {
            accounts.add(DepositAccount(
              m,
              n,
              no,
              kind: DepositKind.parse(a['kind']),
              details: a['details'] as String? ?? '',
            ));
          }
        }
      }
    }
    return WalletRequestConfig(
      enabled: d['enabled'] != false,
      deposit: lim(d['deposit']),
      transfer: lim(d['transfer']),
      depositAccounts: accounts,
      depositNote: d['depositNote'] as String? ?? '',
    );
  }
}

/// wallet_requests/{id} (owner-readable).
class WalletRequest {
  final String id;
  final String type; // 'deposit' | 'transfer'
  final String status; // pending | approved | rejected | cancelled
  final double amount;

  /// Set by the server from the wallet / user's location currency.
  final String? currencyCode;
  final String? recipientName;
  final String? reference;
  final String? note;
  final String? method;

  /// Rejection reason (only shown for rejected requests).
  final String? decisionNote;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  const WalletRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    this.currencyCode,
    this.recipientName,
    this.reference,
    this.note,
    this.method,
    this.decisionNote,
    this.createdAt,
    this.decidedAt,
  });

  bool get isPending => status == 'pending';

  String get label => type == 'transfer' ? 'Send' : 'Top up';

  factory WalletRequest.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? const <String, dynamic>{};
    return WalletRequest(
      id: s.id,
      type: d['type'] as String? ?? 'deposit',
      status: d['status'] as String? ?? 'pending',
      amount: _amount(d['amount']) ?? 0,
      currencyCode: d['currencyCode'] as String?,
      recipientName: d['recipientName'] as String?,
      reference: d['reference'] as String?,
      note: d['note'] as String?,
      method: d['method'] as String?,
      decisionNote: d['status'] == 'rejected' ? d['decisionNote'] as String? : null,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
      decidedAt: d['decidedAt'] is Timestamp
          ? (d['decidedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class WalletRecipient {
  final String id;
  final String name; // masked by the server
  final String? code;
  final String? photoUrl;

  /// The recipient's wallet currency (USD / PHP), for a converted preview.
  final String currencyCode;
  const WalletRecipient(
    this.id,
    this.name,
    this.code,
    this.photoUrl, [
    this.currencyCode = 'USD',
  ]);
}

class WalletRequestsService {
  WalletRequestsService._();

  static final _db = FirebaseFirestore.instance;

  static Stream<WalletRequestConfig> configStream() => _db
      .collection('general_config')
      .doc('wallet_requests')
      .snapshots()
      .map((s) => WalletRequestConfig.fromMap(s.data()))
      .handleError((Object e) => debugPrint('[WalletRequests] config: $e'));

  static Future<WalletRequestConfig> fetchConfig() async {
    try {
      final s = await _db.collection('general_config').doc('wallet_requests').get();
      return WalletRequestConfig.fromMap(s.data());
    } catch (e) {
      debugPrint('[WalletRequests] config read failed: $e');
      return WalletRequestConfig.closed;
    }
  }

  /// The user's pending request, if any (only one is allowed at a time).
  static Stream<WalletRequest?> pendingStream(String uid) => _db
      .collection('wallet_requests')
      .where('userId', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .limit(1)
      .snapshots()
      .map((q) => q.docs.isEmpty ? null : WalletRequest.fromSnapshot(q.docs.first));

  /// The user's newest requests (needs the userId+createdAt index).
  static Stream<List<WalletRequest>> requestsStream(String uid, {int limit = 30}) => _db
      .collection('wallet_requests')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(WalletRequest.fromSnapshot).toList());

  static HttpsCallable _fn(String name) =>
      FirebaseFunctions.instanceFor(region: _functionsRegion).httpsCallable(name);

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[WalletRequests] ${e.code}: ${e.message}');
      throw WalletRequestException(switch (e.code) {
        'unavailable' || 'deadline-exceeded' =>
          "Couldn't reach Giggre. Check your connection and try again.",
        'internal' || 'unknown' => 'Something went wrong. Please try again.',
        _ => e.message ?? 'Something went wrong. Please try again.',
      });
    }
  }

  static String newClientRequestId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static Future<WalletRecipient> lookupRecipient(String query) => _guard(() async {
    final res = await _fn('lookupWalletRecipient').call({'query': query});
    final d = Map<String, dynamic>.from(res.data as Map);
    return WalletRecipient(
      d['recipientId'] as String,
      d['name'] as String? ?? 'Giggre user',
      d['code'] as String?,
      d['photoUrl'] as String?,
      d['currencyCode'] as String? ?? 'USD',
    );
  });

  /// Uploads a payment screenshot; returns (path, downloadUrl).
  static Future<(String, String)> uploadProof({
    required String uid,
    required String clientRequestId,
    required File file,
  }) async {
    final path = 'wallet_proofs/$uid/$clientRequestId.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return (path, await ref.getDownloadURL());
  }

  static Future<String> createTopUp({
    required double amount,
    required String method,
    required DepositKind kind,
    required String reference,
    required String clientRequestId,
    String? proofPath,
    String? proofUrl,
    String? note,
  }) => _guard(() async {
    final res = await _fn('createWalletRequest').call({
      'type': 'deposit',
      'amount': amount,
      'method': method,
      'methodKind': kind.name,
      'reference': reference,
      'clientRequestId': clientRequestId,
      'proofPath': ?proofPath,
      'proofUrl': ?proofUrl,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return (res.data as Map)['requestId'] as String;
  });

  static Future<String> createSend({
    required double amount,
    required String recipientId,
    required String clientRequestId,
    String? note,
  }) => _guard(() async {
    final res = await _fn('createWalletRequest').call({
      'type': 'transfer',
      'amount': amount,
      'recipientId': recipientId,
      'clientRequestId': clientRequestId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return (res.data as Map)['requestId'] as String;
  });

  static Future<void> cancel(String requestId) => _guard(
    () => _fn('cancelWalletRequest').call({'requestId': requestId}),
  );
}
