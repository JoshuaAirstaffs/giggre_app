import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../gig_shared/active_gig_theme.dart';
import '../../services/quick_gig_matching_service.dart';
import 'quick_gig_search_painter.dart';

enum _SearchPhase { searching, found, accepted, empty, cancelled }

const _kSlotColors = [kBlue, Color(0xFF8B5CF6), Color(0xFFE0762E)];
const _kSlotOffsets = [Offset(0, -58), Offset(50, 29), Offset(-50, 29)];

const _kMessages = [
  'Searching nearby workers…',
  'Checking availability…',
  'Matching job requirements…',
];

/// Animated "finding a worker" bottom sheet for a quick gig, driven live by
/// the gig's Firestore status (written by [QuickGigMatchingService]):
/// scanning/in_progress → searching (an offered-but-unaccepted worker still
/// reads as "searching" to the host), navigating/arrived/working/completed →
/// accepted, no_worker → empty, cancelled → cancelled.
class QuickGigSearchSheet extends StatefulWidget {
  final String gigId;
  final GeoPoint gigLocation;
  final VoidCallback onDone;

  const QuickGigSearchSheet({
    super.key,
    required this.gigId,
    required this.gigLocation,
    required this.onDone,
  });

  static Future<void> show({
    required BuildContext context,
    required String gigId,
    required GeoPoint gigLocation,
    required VoidCallback onDone,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickGigSearchSheet(
        gigId: gigId,
        gigLocation: gigLocation,
        onDone: onDone,
      ),
    );
  }

  @override
  State<QuickGigSearchSheet> createState() => _QuickGigSearchSheetState();
}

class _QuickGigSearchSheetState extends State<QuickGigSearchSheet>
    with TickerProviderStateMixin {
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final AnimationController _confirmController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  late final Animation<double> _confirmScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.3)
          .chain(CurveTween(curve: const Cubic(0.34, 1.56, 0.64, 1.0))),
      weight: 40,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
  ]).animate(_confirmController);

  StreamSubscription<DocumentSnapshot>? _gigSub;
  _SearchPhase _phase = _SearchPhase.searching;
  final List<bool> _slotFilled = [false, false, false];
  int _messageIndex = 0;
  int _seconds = 0;
  String? _workerName;
  String? _assignedWorkerId;
  DateTime? _searchStartedAt;
  bool _dispatching = false;
  bool _cancelling = false;
  bool _actioned = false;

  Timer? _secondsTimer;
  Timer? _messageTimer;
  Timer? _slotLoopTimer;
  final List<Timer> _fillTimers = [];

  @override
  void initState() {
    super.initState();
    _secondsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _startSearchingLoops();
    _gigSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(widget.gigId)
        .snapshots()
        .listen(_onGigUpdate);
  }

  @override
  void dispose() {
    _gigSub?.cancel();
    _secondsTimer?.cancel();
    _messageTimer?.cancel();
    _slotLoopTimer?.cancel();
    for (final t in _fillTimers) {
      t.cancel();
    }
    _orbitController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onGigUpdate(DocumentSnapshot snap) {
    if (!mounted || _actioned || !snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final status = data['status'] as String? ?? 'scanning';
    _workerName = data['assignedWorkerName'] as String?;
    _assignedWorkerId = data['assignedWorkerId'] as String?;

    final startedAt = (data['searchStartedAt'] as Timestamp?)?.toDate();
    if (startedAt != null && startedAt != _searchStartedAt) {
      _searchStartedAt = startedAt;
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      setState(() => _seconds = elapsed < 0 ? 0 : elapsed);
    }

    final newPhase = switch (status) {
      'scanning' => _SearchPhase.searching,
      'in_progress' => _SearchPhase.found,
      'navigating' ||
      'arrived' ||
      'working' ||
      'task_complete' ||
      'payment' ||
      'completed' => _SearchPhase.accepted,
      'no_worker' => _SearchPhase.empty,
      'cancelled' || 'cancellation_requested' => _SearchPhase.cancelled,
      _ => _phase,
    };
    if (newPhase != _phase) _transitionTo(newPhase);
  }

  void _transitionTo(_SearchPhase newPhase) {
    final previous = _phase;
    setState(() => _phase = newPhase);

    switch (newPhase) {
      case _SearchPhase.searching:
      case _SearchPhase.found:
        _pulseController.repeat(reverse: true);
        _shakeController.value = 0;
        _confirmController.value = 0;
        if (previous == _SearchPhase.empty ||
            previous == _SearchPhase.accepted ||
            previous == _SearchPhase.cancelled) {
          setState(() {
            _slotFilled[0] = false;
            _slotFilled[1] = false;
            _slotFilled[2] = false;
          });
        }
        _startSearchingLoops();
        break;
      case _SearchPhase.accepted:
        _stopSearchingLoops();
        _fillAllSlots();
        if (previous != _SearchPhase.accepted) {
          _confirmController.forward(from: 0);
        }
        break;
      case _SearchPhase.empty:
        _stopSearchingLoops();
        _pulseController.stop();
        _shakeController.forward(from: 0);
        break;
      case _SearchPhase.cancelled:
        _stopSearchingLoops();
        _pulseController.stop();
        break;
    }
  }

  void _startSearchingLoops() {
    _messageTimer?.cancel();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) {
        setState(() => _messageIndex = (_messageIndex + 1) % _kMessages.length);
      }
    });

    _slotLoopTimer?.cancel();
    var step = 0;
    _slotLoopTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted) return;
      setState(() {
        if (step < 3) {
          _slotFilled[step] = true;
        } else {
          _slotFilled[0] = false;
          _slotFilled[1] = false;
          _slotFilled[2] = false;
        }
      });
      step = (step + 1) % 4;
    });
  }

  void _stopSearchingLoops() {
    _messageTimer?.cancel();
    _slotLoopTimer?.cancel();
  }

  void _fillAllSlots() {
    for (final t in _fillTimers) {
      t.cancel();
    }
    _fillTimers.clear();
    for (var i = 0; i < 3; i++) {
      if (_slotFilled[i]) continue;
      _fillTimers.add(Timer(Duration(milliseconds: 150 * i), () {
        if (mounted) setState(() => _slotFilled[i] = true);
      }));
    }
  }

  Future<void> _onCancelPressed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SearchCancelDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    final db = FirebaseFirestore.instance;
    final workerToFree = _assignedWorkerId;
    await db.collection('quick_gigs').doc(widget.gigId).update({
      'status': 'cancelled',
      'assignedWorkerId': null,
      'assignedWorkerName': null,
      'cancelledAt': FieldValue.serverTimestamp(),
    });
    if (workerToFree != null && workerToFree.isNotEmpty) {
      await db.collection('users').doc(workerToFree).update({
        'slot': 'AVAILABLE',
      });
    }
    if (mounted) {
      setState(() => _cancelling = false);
      _transitionTo(_SearchPhase.cancelled);
    }
  }

  Future<void> _onSearchAgainPressed() async {
    if (_dispatching) return;
    setState(() => _dispatching = true);
    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(widget.gigId)
        .update({
          'status': 'scanning',
          'assignedWorkerId': null,
          'assignedWorkerName': null,
          'searchStartedAt': FieldValue.serverTimestamp(),
          'exclusionList': [],
        });
    QuickGigMatchingService.startAutoSearch(
      gigId: widget.gigId,
      gigLocation: widget.gigLocation,
    );
    if (mounted) {
      setState(() {
        _dispatching = false;
        _seconds = 0;
      });
      _transitionTo(_SearchPhase.searching);
    }
  }

  void _onButtonPressed() {
    if (_actioned) return;
    switch (_phase) {
      case _SearchPhase.searching:
      case _SearchPhase.found:
        _onCancelPressed();
        break;
      case _SearchPhase.empty:
        _onSearchAgainPressed();
        break;
      case _SearchPhase.accepted:
      case _SearchPhase.cancelled:
        _actioned = true;
        widget.onDone();
        break;
    }
  }

  String get _statusText => switch (_phase) {
        _SearchPhase.searching || _SearchPhase.found =>
          _kMessages[_messageIndex],
        _SearchPhase.accepted => '${_workerName ?? 'Worker'} confirmed',
        _SearchPhase.empty => 'No workers found nearby',
        _SearchPhase.cancelled => 'Search cancelled',
      };

  bool get _isPositiveStatus => _phase == _SearchPhase.accepted;

  String get _timeText {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: activeGigCardBg(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHero(isDark),
          const SizedBox(height: 20),
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _isPositiveStatus
                  ? kActiveGigSuccessGreen
                  : activeGigTextSecondary(isDark),
            ),
          ),
          if (_phase == _SearchPhase.searching ||
              _phase == _SearchPhase.found) ...[
            const SizedBox(height: 4),
            Text(
              'Searching for $_timeText',
              style: TextStyle(fontSize: 12, color: activeGigTextMuted(isDark)),
            ),
          ],
          const SizedBox(height: 22),
          _buildButton(isDark),
        ],
      ),
    );
  }

  Widget _buildHero(bool isDark) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: Listenable.merge(
          [_orbitController, _pulseController, _shakeController, _confirmController],
        ),
        builder: (context, _) {
          final shakeX = _phase == _SearchPhase.empty
              ? 6 *
                  math.sin(_shakeController.value * 4 * math.pi) *
                  (1 - _shakeController.value)
              : 0.0;
          final pulseT = Curves.easeInOut.transform(_pulseController.value);
          final bubbleScale =
              _phase == _SearchPhase.empty ? 1.0 : 1 + (pulseT * 0.06);

          return Transform.translate(
            offset: Offset(shakeX, 0),
            child: Container(
              decoration: BoxDecoration(
                color: kAmber,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                    angle: _orbitController.value * 2 * math.pi,
                    child: CustomPaint(
                      size: const Size(156, 156),
                      painter: QuickGigDashedRingPainter(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  for (var i = 0; i < 3; i++) _buildSlot(i),
                  Transform.scale(
                    scale: bubbleScale,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: Icon(
                        Icons.search,
                        size: 26,
                        color: _phase == _SearchPhase.empty
                            ? activeGigTextMuted(isDark)
                            : kAmber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlot(int index) {
    final filled = _slotFilled[index];
    final isConfirming = index == 0 && _phase == _SearchPhase.accepted;
    final revealed = isConfirming && _confirmController.value >= 0.35;
    final color = revealed ? kActiveGigSuccessGreen : _kSlotColors[index];
    final scale = isConfirming ? _confirmScale.value : 1.0;

    return QuickGigAvatarSlot(
      offset: _kSlotOffsets[index],
      color: color,
      filled: filled,
      confirmed: revealed,
      scale: scale,
    );
  }

  Widget _buildButton(bool isDark) {
    final busy = _dispatching || _cancelling;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : _onButtonPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: activeGigCardBorder(isDark)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                switch (_phase) {
                  _SearchPhase.empty => Icons.refresh,
                  _SearchPhase.accepted => Icons.arrow_forward_rounded,
                  _SearchPhase.cancelled => Icons.check,
                  _ => Icons.close,
                },
                size: 16,
              ),
        label: Text(switch (_phase) {
          _SearchPhase.empty => 'Search again',
          _SearchPhase.accepted => 'View gig',
          _SearchPhase.cancelled => 'Close',
          _ => 'Cancel search',
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cancel-search confirmation — cancelling while still searching takes effect
//  immediately (no admin review, since no worker has committed to the gig yet).
// ─────────────────────────────────────────────────────────────────────────────
class _SearchCancelDialog extends StatelessWidget {
  const _SearchCancelDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: activeGigCardBg(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Cancel search?',
        style: TextStyle(color: activeGigTextPrimary(isDark)),
      ),
      content: Text(
        'This will immediately cancel the gig and stop the search. This can\'t be undone.',
        style: TextStyle(fontSize: 13, color: activeGigTextSecondary(isDark)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep searching'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Cancel gig',
            style: TextStyle(color: kActiveGigDestructiveRed),
          ),
        ),
      ],
    );
  }
}
