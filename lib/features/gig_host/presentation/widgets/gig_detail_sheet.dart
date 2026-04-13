import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Detail Sheet  –  shown when host taps a gig card
//  Displays live task details + map tracking of the assigned worker (if any)
// ─────────────────────────────────────────────────────────────────────────────
class GigDetailSheet extends StatefulWidget {
  final String gigId;
  final String gigType; // 'quick' | 'open' | 'offered'

  const GigDetailSheet({
    super.key,
    required this.gigId,
    required this.gigType,
  });

  @override
  State<GigDetailSheet> createState() => _GigDetailSheetState();
}

class _GigDetailSheetState extends State<GigDetailSheet> {
  Map<String, dynamic>? _data;
  LatLng? _workerLocation;
  StreamSubscription? _gigSub;
  StreamSubscription? _workerSub;
  String? _trackedWorkerId;

  String get _collection {
    switch (widget.gigType) {
      case 'open':    return 'open_gigs';
      case 'offered': return 'offered_gigs';
      default:        return 'quick_gigs';
    }
  }

  static const _activeStatuses = [
    'in_progress', 'navigating', 'arrived', 'working', 'task_complete', 'payment',
  ];

  @override
  void initState() {
    super.initState();
    _gigSub = FirebaseFirestore.instance
        .collection(_collection)
        .doc(widget.gigId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data()!;
      setState(() => _data = data);
      // Watch worker location when a worker is assigned
      final wid = data['workerId'] as String? ??
                  data['assignedWorkerId'] as String?;
      if (wid != null && wid.isNotEmpty && wid != _trackedWorkerId) {
        _trackedWorkerId = wid;
        _startWorkerStream(wid);
      }
    }, onError: (e) => debugPrint('[GigDetailSheet] gig stream error: $e'));
  }

  void _startWorkerStream(String uid) {
    _workerSub?.cancel();
    _workerSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final geo = snap.data()?['location'] as GeoPoint?;
      if (geo != null) {
        setState(() => _workerLocation = LatLng(geo.latitude, geo.longitude));
      }
    }, onError: (e) => debugPrint('[GigDetailSheet] worker stream error: $e'));
  }

  @override
  void dispose() {
    _gigSub?.cancel();
    _workerSub?.cancel();
    super.dispose();
  }

  Future<void> _confirmCompleted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Gig Completed',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Confirm that the gig worker has completed the task?\nThis will release their payment.',
          style: TextStyle(color: kSub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final data = _data;
    if (data == null) return;
    final db = FirebaseFirestore.instance;
    final workerId = data['workerId'] as String? ??
                     data['assignedWorkerId'] as String?;
    final workerName = data['assignedWorkerName'] as String? ??
                       data['workerName'] as String? ?? 'Worker';
    await Future.wait([
      db.collection(_collection).doc(widget.gigId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      }),
      if (workerId != null && workerId.isNotEmpty)
        db.collection('users').doc(workerId).update({'slot': 'AVAILABLE'}),
    ]);
    if (!mounted) return;
    if (workerId != null && workerId.isNotEmpty) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RatingDialog(
          workerId: workerId,
          workerName: workerName,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final data = _data;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        if (data == null) {
          return Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: kAmber, strokeWidth: 2),
            ),
          );
        }

        final status = data['status'] as String? ?? '';
        final title = data['title'] as String? ?? 'Gig';
        final description = data['description'] as String? ?? '';
        final budget = (data['budget'] as num?)?.toDouble() ?? 0;
        final address = data['address'] as String? ?? '';
        final geo = data['location'] as GeoPoint?;
        final gigLocation =
            geo != null ? LatLng(geo.latitude, geo.longitude) : null;
        final workerName = data['assignedWorkerName'] as String? ??
                           data['workerName'] as String? ?? '';
        final isActive = _activeStatuses.contains(status);
        final isTaskComplete = status == 'task_complete';
        const green = Color(0xFF22C55E);

        // Stepper config for quick gigs
        const stepStatuses = [
          'navigating', 'arrived', 'working', 'task_complete', 'payment', 'completed'
        ];
        const stepLabels = [
          'On the way', 'Arrived', 'Working', 'Done', 'Payment', 'Completed'
        ];
        const stepIcons = [
          Icons.directions_rounded,
          Icons.location_on_rounded,
          Icons.work_rounded,
          Icons.check_circle_outline_rounded,
          Icons.payment_rounded,
          Icons.verified_rounded,
        ];
        final stepIndex =
            stepStatuses.indexOf(status).clamp(0, stepStatuses.length - 1);

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              // ── Drag handle ────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Title + status badge ───────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 4),
              _TypeBadge(gigType: widget.gigType),
              const SizedBox(height: 16),

              // ── Map: gig location + live worker pin ───────────────
              if (gigLocation != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 220,
                    child: _GigTrackingMap(
                      gigLocation: gigLocation,
                      workerLocation:
                          (isActive && _workerLocation != null)
                              ? _workerLocation
                              : null,
                    ),
                  ),
                ),
                if (isActive && _workerLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Worker location is live',
                          style: TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              // ── Progress stepper (quick gigs with active worker) ───
              if (widget.gigType == 'quick' && isActive) ...[
                Text(
                  'Task Progress',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(stepStatuses.length, (i) {
                      final isStepActive = i == stepIndex;
                      final isDone = i < stepIndex;
                      final dotColor = (isStepActive || isDone) ? green : kSub;
                      final dotBg = isDone
                          ? green
                          : isStepActive
                              ? green.withValues(alpha: 0.12)
                              : (isDark
                                  ? kBorder.withValues(alpha: 0.5)
                                  : Colors.grey.withValues(alpha: 0.12));
                      return Row(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: dotBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (isStepActive || isDone)
                                        ? green
                                        : kSub.withValues(alpha: 0.3),
                                    width: isStepActive ? 2 : 1,
                                  ),
                                ),
                                child: Icon(
                                  isDone
                                      ? Icons.check_rounded
                                      : stepIcons[i],
                                  size: 14,
                                  color: isDone ? Colors.white : dotColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                stepLabels[i],
                                style: TextStyle(
                                  fontSize: 9,
                                  color: (isStepActive || isDone) ? green : kSub,
                                  fontWeight: isStepActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          if (i < stepStatuses.length - 1)
                            Container(
                              width: 20,
                              height: 1.5,
                              margin: const EdgeInsets.only(bottom: 14),
                              color: i < stepIndex
                                  ? green
                                  : kSub.withValues(alpha: 0.25),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Task details ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (description.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.notes_rounded,
                        label: description,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _DetailRow(
                      icon: Icons.attach_money_rounded,
                      label: '₱${budget.toStringAsFixed(0)}',
                      iconColor: kAmber,
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: address,
                      ),
                    ],
                    if (workerName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.person_outline_rounded,
                        label: workerName,
                        iconColor: kBlue,
                      ),
                    ],
                  ],
                ),
              ),

              // ── Gig Completed button (host confirms when done) ─────
              if (isTaskComplete) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _confirmCompleted,
                    icon: const Icon(Icons.verified_rounded, size: 20),
                    label: const Text(
                      'Gig Completed',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Map showing gig location pin + live worker pin
// ─────────────────────────────────────────────────────────────────────────────
class _GigTrackingMap extends StatelessWidget {
  final LatLng gigLocation;
  final LatLng? workerLocation;

  const _GigTrackingMap({
    required this.gigLocation,
    this.workerLocation,
  });

  @override
  Widget build(BuildContext context) {
    final center = workerLocation != null
        ? LatLng(
            (gigLocation.latitude + workerLocation!.latitude) / 2,
            (gigLocation.longitude + workerLocation!.longitude) / 2,
          )
        : gigLocation;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: workerLocation != null ? 14.0 : 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.app',
        ),
        MarkerLayer(
          markers: [
            // Gig location — amber pin
            Marker(
              point: gigLocation,
              width: 40,
              height: 44,
              child: const Column(
                children: [
                  Icon(Icons.location_on_rounded, color: kAmber, size: 36),
                ],
              ),
            ),
            // Worker live location — blue circle
            if (workerLocation != null)
              Marker(
                point: workerLocation!,
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: kBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: kBlue.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case 'scanning':      return kAmber;
      case 'in_progress':
      case 'navigating':    return kBlue;
      case 'arrived':       return const Color(0xFF06B6D4);
      case 'working':       return const Color(0xFF8B5CF6);
      case 'task_complete': return const Color(0xFF22C55E);
      case 'payment':       return const Color(0xFF22C55E);
      case 'completed':     return const Color(0xFF22C55E);
      case 'open':          return const Color(0xFF22C55E);
      case 'offered':       return const Color(0xFF8B5CF6);
      case 'cancelled':     return Colors.redAccent;
      case 'no_worker':     return Colors.redAccent;
      default:              return kSub;
    }
  }

  String _label() {
    switch (status) {
      case 'scanning':      return 'SCANNING';
      case 'in_progress':   return 'IN PROGRESS';
      case 'navigating':    return 'NAVIGATING';
      case 'arrived':       return 'ARRIVED';
      case 'working':       return 'WORKING';
      case 'task_complete': return 'TASK DONE';
      case 'payment':       return 'PAYMENT';
      case 'completed':     return 'COMPLETED';
      case 'open':          return 'OPEN';
      case 'offered':       return 'OFFERED';
      case 'cancelled':     return 'CANCELLED';
      case 'no_worker':     return 'NO WORKER';
      default:              return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          color: c,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String gigType;
  const _TypeBadge({required this.gigType});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String label;
    switch (gigType) {
      case 'open':
        icon  = Icons.workspace_premium_outlined;
        color = kBlue;
        label = 'Open Gig';
        break;
      case 'offered':
        icon  = Icons.send_rounded;
        color = const Color(0xFF8B5CF6);
        label = 'Offered Gig';
        break;
      default:
        icon  = Icons.flash_on_rounded;
        color = kAmber;
        label = 'Quick Gig';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    this.iconColor = kSub,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Rating Dialog — shown after host confirms gig completed
// ─────────────────────────────────────────────────────────────────────────────
class _RatingDialog extends StatefulWidget {
  final String workerId;
  final String workerName;

  const _RatingDialog({
    required this.workerId,
    required this.workerName,
  });

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _selected = 0;
  bool _submitting = false;

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];
  static const _green = Color(0xFF22C55E);
  static const _starActive = Color(0xFFFACC15);

  Future<void> _submit() async {
    if (_selected == 0) return;
    setState(() => _submitting = true);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('users').doc(widget.workerId).get();
      final data = snap.data() ?? {};
      final currentRating = (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
      final currentCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
      final newCount = currentCount + 1;
      final newRating =
          ((currentRating * currentCount) + _selected) / newCount;
      await db.collection('users').doc(widget.workerId).update({
        'ratingAsWorker': double.parse(newRating.toStringAsFixed(2)),
        'ratingCount': newCount,
      });
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final label = _selected > 0 ? _labels[_selected] : 'Tap a star to rate';

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: _green, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            'Rate Your Worker',
            style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was ${widget.workerName}?',
            style: const TextStyle(color: kSub, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selected = starNum),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    starNum <= _selected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: starNum <= _selected ? _starActive : kSub,
                    size: 40,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                color: _selected > 0 ? _starActive : kSub,
                fontSize: 13,
                fontWeight: _selected > 0
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Skip',
                      style: TextStyle(color: kSub, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      (_selected == 0 || _submitting) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _green.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
