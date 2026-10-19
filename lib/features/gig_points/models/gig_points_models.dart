import 'package:cloud_firestore/cloud_firestore.dart';

// Read-only views of the Gig Points data written by functions/src/gigPoints.ts.
// The app never writes any of these — firestore.rules denies it — so there
// are deliberately no toMap() methods here.

int _int(Object? v) => v is num ? v.toInt() : 0;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

/// gig_points/{uid}
class GigPointsBalance {
  /// Credited, spendable points. Only ever moved by the backend once an
  /// award is recorded — pending points are never included here.
  final int balance;

  /// Host-approved tasks still waiting on payment confirmation.
  final int pendingPoints;
  final int lifetimeEarned;

  /// Points reserved by withdraw / transfer requests waiting for admin
  /// review. Already taken out of [balance]; returned if the request is
  /// rejected or cancelled.
  final int heldPoints;

  /// Tasks whose points have been credited.
  final int gigsRewarded;
  final DateTime? lastAwardedAt;

  /// True when this came from the device cache rather than the server
  /// (e.g. offline) — the screen says so instead of presenting it as live.
  final bool fromCache;

  const GigPointsBalance({
    required this.balance,
    required this.pendingPoints,
    required this.lifetimeEarned,
    required this.gigsRewarded,
    this.heldPoints = 0,
    this.lastAwardedAt,
    this.fromCache = false,
  });

  factory GigPointsBalance.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? const <String, dynamic>{};
    final pending = _int(d['pendingPoints']);
    return GigPointsBalance(
      balance: _int(d['balance']),
      // Can't legitimately go below zero; guard against a stale read.
      pendingPoints: pending < 0 ? 0 : pending,
      lifetimeEarned: _int(d['lifetimeEarned']),
      gigsRewarded: _int(d['gigsRewarded']),
      heldPoints: _int(d['heldPoints']) < 0 ? 0 : _int(d['heldPoints']),
      lastAwardedAt: _date(d['lastAwardedAt']),
      fromCache: snap.metadata.isFromCache,
    );
  }
}

/// Ledger entry state, set only by the backend.
enum GigPointsStatus {
  /// Host approved the work; waiting for payment confirmation.
  pending,

  /// Recorded and added to the balance.
  credited,

  /// The gig ended (cancelled etc.) before completion — nothing awarded.
  voided;

  static GigPointsStatus parse(Object? v) => switch (v) {
    'pending' => GigPointsStatus.pending,
    'voided' => GigPointsStatus.voided,
    // Every ledger entry is server-written. Entries from before statuses
    // existed were only ever written at credit time.
    _ => GigPointsStatus.credited,
  };

  String get label => switch (this) {
    GigPointsStatus.pending => 'Pending',
    GigPointsStatus.credited => 'Credited',
    GigPointsStatus.voided => 'Voided',
  };
}

/// The five states a task's reward can be in, as shown to the user. Kept
/// separate from [GigPointsStatus] because the first two come from the gig
/// itself (no ledger entry exists yet) — only the backend creates entries.
enum RewardStage {
  /// The gig's configured reward; nothing has been earned yet.
  notYetEarned,

  /// Worker finished; the host hasn't approved the work yet.
  awaitingApproval,

  /// Host approved; the reward is recorded as pending until payment is
  /// confirmed and the backend credits it.
  approvedProcessing,

  /// Recorded and added to the available balance.
  credited,

  /// The gig was cancelled / closed / declined — no reward.
  notEligible;

  String get label => switch (this) {
    RewardStage.notYetEarned => 'Not yet earned',
    RewardStage.awaitingApproval => 'Awaiting approval',
    RewardStage.approvedProcessing => 'Approved · processing',
    RewardStage.credited => 'Credited',
    RewardStage.notEligible => 'Not eligible',
  };

  String get explanation => switch (this) {
    RewardStage.notYetEarned =>
      'This is the reward set for this gig. You earn it once you finish the '
          'work and the host approves it.',
    RewardStage.awaitingApproval =>
      "You've marked the work as done. Waiting for the host to approve it.",
    RewardStage.approvedProcessing =>
      'The host approved your work. The points are added to your available '
          'balance once payment is confirmed.',
    RewardStage.credited => 'Recorded and added to your available balance.',
    RewardStage.notEligible =>
      "The gig didn't finish, so it doesn't qualify for a reward.",
  };

  /// Only credited rewards are part of the available balance.
  bool get countsTowardBalance => this == RewardStage.credited;
}

/// How a reward amount was arrived at. Mirrors RewardBasis in
/// functions/src/gigPoints.ts. There is deliberately no "default" basis:
/// a task with neither value set is not awarded automatically.
enum RewardBasis {
  /// The task's own reward (`gigPointsReward`, admin-set) — takes precedence.
  task,

  /// The configured reward for the task's type.
  taskType;

  static RewardBasis? parse(Object? v) => switch (v) {
    'task' => RewardBasis.task,
    'task_type' => RewardBasis.taskType,
    _ => null,
  };
}

/// A valid reward is a non-negative whole number — anything else is
/// rejected, never rounded (same rule as rewardInt() in
/// functions/src/gigPoints.ts). A whole-number double (10.0) is accepted
/// because the Firebase console can store "10" that way; 12.5 is not.
int? validReward(Object? v) {
  if (v is int) return v >= 0 ? v : null;
  if (v is double && v.isFinite && v >= 0 && v == v.truncateToDouble()) {
    return v.toInt();
  }
  return null;
}

String gigTypeLabel(String? gigType) => switch (gigType) {
  'quick' => 'Quick Gig',
  'open' => 'Open Gig',
  'offered' => 'Offered Gig',
  _ => 'Gig',
};

/// "Why this amount" copy, shared by ledger entries and live quotes.
String explainRewardAmount({
  required int points,
  required RewardBasis? basis,
  required String? gigType,
  int? configuredPoints,
  int? cappedAt,
}) {
  final type = gigTypeLabel(gigType);
  final base = switch (basis) {
    RewardBasis.task => 'Reward set for this specific gig: $points pts.',
    RewardBasis.taskType => 'Standard reward for a $type: $points pts.',
    null => 'Reward for completing a $type: $points pts.',
  };
  if (cappedAt != null && configuredPoints != null) {
    return '$base Capped at the $cappedAt-point per-gig maximum '
        '(configured: $configuredPoints).';
  }
  return base;
}

String _voidReasonText(String? reason) => switch (reason) {
  'no_worker' => 'the gig closed without being completed',
  'declined' => 'the gig offer was declined',
  _ => 'the gig was cancelled before completion',
};

/// gig_points/{uid}/transactions/{txId}
class GigPointsTransaction {
  final String id;

  /// 'earn' (a task), 'adjustment' (admin correction), or a points
  /// movement: 'deposit', 'withdraw', 'transfer_out', 'transfer_in'
  /// (functions/src/gigPointsRequests.ts).
  final String type;
  final GigPointsStatus status;
  final int points;
  final String? gigId;
  final String? gigCollection;
  final String? slotId;
  final String? gigTitle;
  final String? gigType;
  final String? description;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? completedAt;
  final DateTime? creditedAt;
  final DateTime? voidedAt;
  final RewardBasis? rewardBasis;
  final int? configuredPoints;
  final int? rewardCappedAt;
  final String? voidReason;

  /// Movement entries only: the request it belongs to, the other user of a
  /// transfer, and 'admin' when Giggre made it directly.
  final String? requestId;
  final String? counterpartyName;
  final String? counterpartyCode;
  final String? source;
  final String? note;
  final String? reference;

  const GigPointsTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.points,
    this.gigId,
    this.gigCollection,
    this.slotId,
    this.gigTitle,
    this.gigType,
    this.description,
    this.createdAt,
    this.approvedAt,
    this.completedAt,
    this.creditedAt,
    this.voidedAt,
    this.rewardBasis,
    this.configuredPoints,
    this.rewardCappedAt,
    this.voidReason,
    this.requestId,
    this.counterpartyName,
    this.counterpartyCode,
    this.source,
    this.note,
    this.reference,
  });

  static const movementTypes = {
    'deposit',
    'withdraw',
    'transfer_out',
    'transfer_in',
  };

  /// A deposit / withdrawal / transfer rather than a task reward.
  bool get isMovement => movementTypes.contains(type);
  bool get byAdmin => source == 'admin';

  bool get isAdjustment => type == 'adjustment';
  bool get isCredited => status == GigPointsStatus.credited;

  RewardStage get stage => switch (status) {
    GigPointsStatus.pending => RewardStage.approvedProcessing,
    GigPointsStatus.credited => RewardStage.credited,
    GigPointsStatus.voided => RewardStage.notEligible,
  };

  /// Status as worded for this entry — movements aren't rewards, so they
  /// get request wording instead of the reward stages.
  String get statusLabel {
    if (!isMovement) return stage.label;
    return switch (status) {
      GigPointsStatus.pending => 'Pending review',
      GigPointsStatus.credited => 'Completed',
      GigPointsStatus.voided =>
        voidReason == 'cancelled' ? 'Cancelled' : 'Rejected',
    };
  }

  String get statusExplanation {
    if (isAdjustment) return 'Adjusted by Giggre support.';
    if (!isMovement) return stage.explanation;
    final held = type == 'withdraw' || type == 'transfer_out';
    return switch (status) {
      GigPointsStatus.pending => held
          ? 'Waiting for a Giggre admin to review it. The points are on hold '
                'and come back to you if it is rejected or you cancel it.'
          : 'Waiting for a Giggre admin to confirm your payment. The points '
                'are added once it is approved.',
      GigPointsStatus.credited => byAdmin
          ? 'Made by Giggre.'
          : 'Approved by Giggre and applied to your balance.',
      GigPointsStatus.voided => voidReason == 'cancelled'
          ? 'You cancelled this request.${held ? ' The held points were returned.' : ''}'
          : 'Giggre rejected this request.${held ? ' The held points were returned.' : ''}',
    };
  }

  /// Why the user received (or would have received) this amount.
  String get amountExplanation {
    if (isMovement) {
      final who = counterpartyName == null
          ? ''
          : ' ${type == 'transfer_in' ? 'from' : 'to'} $counterpartyName'
                '${counterpartyCode == null ? '' : ' ($counterpartyCode)'}';
      final base = switch (type) {
        'deposit' => 'Points deposited to your balance.',
        'withdraw' => 'Points withdrawn from your balance.',
        'transfer_out' => 'Points you sent$who.',
        _ => 'Points you received$who.',
      };
      final n = note?.isNotEmpty == true ? ' Note: $note' : '';
      return '$base$n';
    }
    if (isAdjustment) {
      final why = description?.isNotEmpty == true ? ': $description' : '.';
      return 'Manual adjustment by Giggre support$why';
    }
    final amount = explainRewardAmount(
      points: points,
      basis: rewardBasis,
      gigType: gigType,
      configuredPoints: configuredPoints,
      cappedAt: rewardCappedAt,
    );
    return switch (status) {
      GigPointsStatus.voided =>
        'No points awarded because ${_voidReasonText(voidReason)}. '
            '(Configured reward: $points pts.)',
      GigPointsStatus.pending =>
        '$amount Locked in when the host approved your work.',
      GigPointsStatus.credited => amount,
    };
  }

  String get title {
    if (isMovement) {
      return switch (type) {
        'deposit' => 'Deposit',
        'withdraw' => 'Withdrawal',
        'transfer_out' => counterpartyName == null
            ? 'Transfer sent'
            : 'Sent to $counterpartyName',
        _ => counterpartyName == null
            ? 'Transfer received'
            : 'From $counterpartyName',
      };
    }
    if (isAdjustment) return points >= 0 ? 'Bonus from Giggre' : 'Points adjustment';
    return gigTitle?.isNotEmpty == true ? gigTitle! : 'Completed gig';
  }

  String get typeLabel => switch (type) {
    'adjustment' => 'Adjustment',
    'deposit' => 'Deposit',
    'withdraw' => 'Withdraw',
    'transfer_out' || 'transfer_in' => 'Transfer',
    _ => gigTypeLabel(gigType),
  };

  /// The date that matters for the entry's current state.
  DateTime? get statusDate => switch (status) {
    GigPointsStatus.credited => creditedAt ?? completedAt ?? createdAt,
    GigPointsStatus.pending => approvedAt ?? createdAt,
    GigPointsStatus.voided => voidedAt ?? createdAt,
  };

  String get statusDateLabel => switch (status) {
    GigPointsStatus.credited =>
      isAdjustment ? 'Adjusted' : (isMovement ? 'Completed' : 'Credited'),
    GigPointsStatus.pending => isMovement ? 'Requested' : 'Approved',
    GigPointsStatus.voided => isMovement ? statusLabel : 'Voided',
  };

  /// Works for query results and single-doc reads alike. Callers reading a
  /// single doc should check `snap.exists` first.
  factory GigPointsTransaction.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? const <String, dynamic>{};
    return GigPointsTransaction(
      id: snap.id,
      type: d['type'] as String? ?? 'earn',
      status: GigPointsStatus.parse(d['status']),
      points: _int(d['points']),
      gigId: d['gigId'] as String?,
      gigCollection: d['gigCollection'] as String?,
      slotId: d['slotId'] as String?,
      gigTitle: d['gigTitle'] as String?,
      gigType: d['gigType'] as String?,
      description: (d['description'] ?? d['reason']) as String?,
      createdAt: _date(d['createdAt']),
      approvedAt: _date(d['approvedAt']),
      completedAt: _date(d['completedAt']),
      creditedAt: _date(d['creditedAt']),
      voidedAt: _date(d['voidedAt']),
      rewardBasis: RewardBasis.parse(d['rewardBasis']),
      configuredPoints: d['configuredPoints'] is num
          ? (d['configuredPoints'] as num).toInt()
          : null,
      rewardCappedAt: d['rewardCappedAt'] is num
          ? (d['rewardCappedAt'] as num).toInt()
          : null,
      voidReason: d['voidReason'] as String?,
      requestId: d['requestId'] as String?,
      counterpartyName: d['counterpartyName'] as String?,
      counterpartyCode: d['counterpartyCode'] as String?,
      source: d['source'] as String?,
      note: d['note'] as String?,
      reference: d['reference'] as String?,
    );
  }
}

/// general_config/gig_points — the centrally configured reward per gig type.
///
/// There are no built-in values: a type with no valid value configured
/// simply has no reward, and a task of that type with no reward of its own
/// isn't awarded automatically (the backend flags it for admins).
/// Read-only and display-only here — functions/src/gigPoints.ts decides
/// every recorded amount.
class GigPointsConfig {
  /// Whether the config doc exists at all.
  final bool exists;
  final bool enabled;

  /// Only the valid per-type values; invalid ones are dropped.
  final Map<String, int> pointsByGigType;

  /// Optional safety cap; null = no cap.
  final int? maxPointsPerGig;

  const GigPointsConfig({
    required this.exists,
    required this.enabled,
    required this.pointsByGigType,
    this.maxPointsPerGig,
  });

  /// No config doc — nothing is configured.
  static const notConfigured = GigPointsConfig(
    exists: false,
    enabled: true,
    pointsByGigType: {},
  );

  bool get hasAnyTypeReward => pointsByGigType.isNotEmpty;

  /// The configured reward for a type, or null if none is set.
  int? pointsFor(String gigType) => pointsByGigType[gigType];

  /// Display-only mirror of quoteReward() in functions/src/gigPoints.ts:
  ///   1. the task's own valid reward, else
  ///   2. the type's configured reward, else
  ///   3. null — no reward configured; nothing is awarded automatically.
  /// Once the host approves, the backend's locked-in value (on the ledger
  /// entry) is shown instead of this.
  RewardQuote? quote({required String gigType, required Object? gigPointsReward}) {
    final task = validReward(gigPointsReward);
    final typeValue = pointsByGigType[gigType];
    final (int, RewardBasis)? picked = task != null
        ? (task, RewardBasis.task)
        : typeValue != null
        ? (typeValue, RewardBasis.taskType)
        : null;
    if (picked == null) return null;
    final (configured, basis) = picked;
    final cap = maxPointsPerGig;
    final points = cap != null && configured > cap ? cap : configured;
    return RewardQuote(
      points: points,
      basis: basis,
      gigType: gigType,
      configuredPoints: configured,
      cappedAt: points < configured ? points : null,
    );
  }

  factory GigPointsConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return notConfigured;
    final byType = <String, int>{};
    final raw = d['pointsByGigType'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = validReward(v);
        if (k is String && n != null) byType[k] = n;
      });
    }
    return GigPointsConfig(
      exists: true,
      enabled: d['enabled'] != false,
      pointsByGigType: byType,
      maxPointsPerGig: validReward(d['maxPointsPerGig']),
    );
  }
}

/// A configured (not yet earned) reward for a specific gig.
class RewardQuote {
  final int points;
  final RewardBasis basis;
  final String gigType;
  final int configuredPoints;
  final int? cappedAt;

  const RewardQuote({
    required this.points,
    required this.basis,
    required this.gigType,
    required this.configuredPoints,
    this.cappedAt,
  });

  String get explanation => explainRewardAmount(
    points: points,
    basis: basis,
    gigType: gigType,
    configuredPoints: configuredPoints,
    cappedAt: cappedAt,
  );
}
