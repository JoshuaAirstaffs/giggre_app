import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:giggre_app/main.dart' show flavor;

final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

// Longest prefix the server stores per word (MAX_PREFIX in
// functions/src/directMessages.ts) — longer queries are cut to it.
const _maxPrefix = 15;

/// One search result, read from publicProfiles/{uid} — never the private
/// users doc, so no email, phone or location is ever loaded here.
class UserSearchResult {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isVerified;
  final double? workerRating;
  final int workerRatingCount;
  final double? hostRating;
  final int hostRatingCount;

  const UserSearchResult({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.isVerified = false,
    this.workerRating,
    this.workerRatingCount = 0,
    this.hostRating,
    this.hostRatingCount = 0,
  });

  factory UserSearchResult.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    (double?, int) rating(Object? v) {
      if (v is! Map) return (null, 0);
      final count = (v['count'] as num?)?.toInt() ?? 0;
      return count > 0 ? ((v['average'] as num?)?.toDouble(), count) : (null, 0);
    }

    final (worker, workerCount) = rating(data['ratingWorker']);
    final (host, hostCount) = rating(data['ratingHost']);
    return UserSearchResult(
      uid: d.id,
      name: (data['name'] as String?) ?? '',
      photoUrl: data['photoUrl'] as String?,
      isVerified: data['isVerified'] == true,
      workerRating: worker,
      workerRatingCount: workerCount,
      hostRating: host,
      hostRatingCount: hostCount,
    );
  }

  /// Which reputation says more about them — their profile opens on it.
  bool get mostlyHost => hostRatingCount > workerRatingCount;
}

/// What [UserSearchService.startChat] opened.
class DirectChatStart {
  final String roomId;

  /// 'pending' (a message request), 'accepted' or 'declined'.
  final String requestStatus;
  final String peerName;

  const DirectChatStart({
    required this.roomId,
    required this.requestStatus,
    required this.peerName,
  });
}

/// A refusal from the server, with a message fit to show the user.
class DirectChatException implements Exception {
  final String message;
  const DirectChatException(this.message);
  @override
  String toString() => message;
}

class UserSearchService {
  static final _db = FirebaseFirestore.instance;

  /// Lowercase, accents removed, single-spaced — must match normalizeName
  /// in functions/src/directMessages.ts or nothing will match.
  static String normalize(String s) {
    const accents = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
    };
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      out.write(accents[ch] ?? ch);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Searchable people whose name starts with [query] (any word, or the
  /// whole name). Leaves out the caller and anyone they've blocked.
  static Future<List<UserSearchResult>> search(
    String query, {
    Set<String> excludeUids = const {},
  }) async {
    var key = normalize(query);
    if (key.length < 2) return const [];
    if (key.length > _maxPrefix) key = key.substring(0, _maxPrefix);

    final snap = await _db
        .collection('publicProfiles')
        .where('searchable', isEqualTo: true)
        .where('nameKeys', arrayContains: key)
        .limit(30)
        .get();
    final me = FirebaseAuth.instance.currentUser?.uid;
    return snap.docs
        .where((d) => d.id != me && !excludeUids.contains(d.id))
        .map(UserSearchResult.fromDoc)
        .where((r) => r.name.isNotEmpty)
        .toList();
  }

  /// Opens (creating if needed) the direct chat with [peerUid]. Someone the
  /// caller hasn't worked with gets a message request.
  static Future<DirectChatStart> startChat(String peerUid) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('startDirectChat')
          .call<Map<String, dynamic>>({'peerUid': peerUid});
      final data = result.data;
      return DirectChatStart(
        roomId: data['roomId'] as String,
        requestStatus: (data['requestStatus'] as String?) ?? 'accepted',
        peerName: (data['peerName'] as String?) ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[UserSearchService] ${e.code}: ${e.message}');
      throw DirectChatException(switch (e.code) {
        'unavailable' || 'deadline-exceeded' =>
          "Couldn't reach Giggre. Check your connection and try again.",
        'internal' || 'unknown' => 'Something went wrong. Please try again.',
        _ => e.message ?? 'Something went wrong. Please try again.',
      });
    }
  }
}
