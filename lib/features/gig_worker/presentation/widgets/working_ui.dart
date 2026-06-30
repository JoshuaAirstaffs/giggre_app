import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:giggre_app/features/call/call_user_action.dart';
import 'package:giggre_app/features/chat/gig_chat_action.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import 'gig_map_section.dart';
import 'worker_payment_confirm_sheet.dart';
import '../../../../core/services/gms_availability.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Gig progress steps
// ─────────────────────────────────────────────────────────────────────────────
enum _GigStep { navigating, arrived, working, taskComplete, payment, completed }

_GigStep _stepFromStatus(String s) {
  switch (s) {
    case 'navigating':    return _GigStep.navigating;
    case 'arrived':       return _GigStep.arrived;
    case 'working':       return _GigStep.working;
    case 'task_complete': return _GigStep.taskComplete;
    case 'payment':       return _GigStep.payment;
    case 'completed':     return _GigStep.completed;
    default:              return _GigStep.navigating;
  }
}

const _stepLabels = ['Navigating', 'Arrived', 'Working', 'Done', 'Payment', 'Completed'];
const _stepIcons = [
  Icons.directions_rounded,
  Icons.location_on_rounded,
  Icons.work_rounded,
  Icons.check_circle_outline_rounded,
  Icons.payment_rounded,
  Icons.verified_rounded,
];

// ─────────────────────────────────────────────────────────────────────────────
//  Route step model + helpers (used by _NavigatingSection)
// ─────────────────────────────────────────────────────────────────────────────
class _RouteStep {
  final String instruction;
  final IconData icon;
  final double distanceM;
  const _RouteStep({required this.instruction, required this.icon, required this.distanceM});
}

String _buildStepInstruction(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
  final type     = maneuver['type'] as String? ?? '';
  final modifier = maneuver['modifier'] as String? ?? '';
  final name     = (step['name'] as String? ?? '').trim();
  final onto     = name.isNotEmpty ? ' onto $name' : '';
  switch (type) {
    case 'depart':    return 'Head out${onto.isNotEmpty ? onto : ''}';
    case 'arrive':    return 'Arrive at destination';
    case 'turn':      return 'Turn ${_stepDir(modifier)}$onto';
    case 'new name':
    case 'continue':  return 'Continue${onto.isEmpty ? ' straight' : onto}';
    case 'merge':     return 'Merge ${_stepDir(modifier)}$onto';
    case 'on ramp':   return 'Take the ramp ${_stepDir(modifier)}';
    case 'off ramp':  return 'Take exit${onto.isNotEmpty ? onto : ''}';
    case 'fork':      return 'Keep ${_stepDir(modifier)} at the fork';
    case 'end of road': return 'Turn ${_stepDir(modifier)} at end of road';
    case 'roundabout':
    case 'rotary': {
      final exit = maneuver['exit'] as int?;
      return exit != null ? 'Take exit $exit at roundabout' : 'Enter the roundabout';
    }
    default: return name.isNotEmpty ? 'Continue on $name' : 'Continue';
  }
}

String _stepDir(String modifier) {
  switch (modifier) {
    case 'uturn':       return 'around';
    case 'sharp right': return 'sharp right';
    case 'right':       return 'right';
    case 'slight right':return 'slightly right';
    case 'slight left': return 'slightly left';
    case 'left':        return 'left';
    case 'sharp left':  return 'sharp left';
    default:            return 'straight';
  }
}

IconData _iconForStepData(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
  final type     = maneuver['type'] as String? ?? '';
  final modifier = maneuver['modifier'] as String? ?? '';
  switch (type) {
    case 'depart':    return Icons.navigation_rounded;
    case 'arrive':    return Icons.location_on_rounded;
    case 'roundabout':
    case 'rotary':    return Icons.roundabout_right_rounded;
    case 'merge':     return Icons.merge_rounded;
    case 'on ramp':
    case 'off ramp':  return Icons.ramp_right_rounded;
    default:
      if (modifier.contains('left'))  return Icons.turn_left_rounded;
      if (modifier.contains('right')) return Icons.turn_right_rounded;
      return Icons.straight_rounded;
  }
}

String _fmtDist(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _fmtEta(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60}h ${m % 60}m';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Working UI — full-screen view shown when a quick gig is active
// ─────────────────────────────────────────────────────────────────────────────
class WorkingUI extends StatefulWidget {
  final GigMarkerData gig;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final String gigCollection;



  const WorkingUI({
    super.key,
    required this.gig,
    required this.onComplete,
    required this.onCancel,
    this.gigCollection = 'quick_gigs',
  });

  @override
  State<WorkingUI> createState() => _WorkingUIState();
}

class _WorkingUIState extends State<WorkingUI> {
  _GigStep _step = _GigStep.navigating;

  _GigStep _lastActiveStep = _GigStep.navigating;
  String _lastStatusString = 'navigating';
  bool _cancelPending = false;

  // Guard: show host rating dialog only once
  bool _ratingShown = false;
  // Guard: handle admin-approved cancellation only once
  bool _cancelledHandled = false;
  // Show arrival confirmation prompt when geofence triggers
  bool _arrivedPromptVisible = false;
  // Guard: show worker payment confirmation only once
  bool _paymentConfirmShown = false;

  // Stopwatch (working step)
  late final Stopwatch _stopwatch;
  late final Timer _timer;
  Duration _elapsed = Duration.zero;
  Duration _elapsedOffset = Duration.zero; // pre-loaded on restore

  // Worker location tracking
  LatLng? _workerLocation;
  StreamSubscription<Position>? _locationSub;
  bool _geofenceTriggered = false;
  static const _arrivedThresholdMeters = 40.0;

  // Actual road route
  List<LatLng> _routePoints = [];
  LatLng? _lastRouteFetch;
  double? _routeDistanceM;
  int? _routeEtaSeconds;
  List<_RouteStep> _routeSteps = [];

  // Firestore live listener
  StreamSubscription? _gigSub;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stopwatch.isRunning) {
        setState(() => _elapsed = _elapsedOffset + _stopwatch.elapsed);
      }
    });
    _listenGig();
    _startLocation();
    _restoreElapsedIfWorking();
  }

  // ── Firestore listener ────────────────────────────────────────────────────
  void _listenGig() {
    _gigSub = FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;

      final status = snap.data()?['status'] as String? ?? 'navigating';

      if (status == 'cancelled' && !_cancelledHandled) {
        _cancelledHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _onAdminCancelled());
        return;
      }

      final isCancelPending = status == 'cancellation_requested';

      final newStep = isCancelPending
          ? _lastActiveStep
          : _stepFromStatus(status);

      if (!isCancelPending) {
        _lastActiveStep = newStep;
        _lastStatusString = status;
      }

      if (newStep != _step || isCancelPending != _cancelPending) {
        setState(() {
          _step = newStep;
          _cancelPending = isCancelPending;
        });
      }

      if (newStep == _GigStep.working && !_stopwatch.isRunning) {
        _stopwatch.start();
      }

      if (newStep == _GigStep.payment && !_paymentConfirmShown) {
        _paymentConfirmShown = true;
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showWorkerPaymentConfirm());
      }

      if (newStep == _GigStep.completed && !_ratingShown) {
        // Only trigger from the stream when the payment sheet was never opened
        // this session (app-restore path). The normal path goes through
        // _onPaymentConfirmed which already handles pop + rating.
        if (!_paymentConfirmShown) {
          _ratingShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showHostRatingAndComplete(snap.data()!);
          });
        }
      }
    }, onError: (e) => debugPrint('[WorkingUI] gig stream error: $e'));
  }
  // ── Location stream + geofence ────────────────────────────────────────────
  Future<void> _startLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return; }
      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() => _workerLocation = loc);
        _checkGeofence(pos);
        // Re-fetch route only when navigating and moved >30 m from last fetch
        if (_step == _GigStep.navigating) {
          // Persist location to Firestore so host can track worker in real-time
          FirebaseFirestore.instance
              .collection(widget.gigCollection)
              .doc(widget.gig.id)
              .update({'workerLocation': GeoPoint(pos.latitude, pos.longitude)})
              .catchError((_) {});

          final gigPos = LatLng(
            widget.gig.position.latitude,
            widget.gig.position.longitude,
          );
          final shouldFetch = _lastRouteFetch == null ||
              Geolocator.distanceBetween(
                _lastRouteFetch!.latitude, _lastRouteFetch!.longitude,
                loc.latitude, loc.longitude,
              ) > 30;
          if (shouldFetch) {
            _lastRouteFetch = loc;
            _fetchRoute(loc, gigPos);
          }
        }
      }, onError: (e) => debugPrint('[WorkingUI] location stream error: $e'));
    } catch (_) {}
  }

  void _checkGeofence(Position pos) {
    if (_geofenceTriggered || _step != _GigStep.navigating) return;
    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      widget.gig.position.latitude, widget.gig.position.longitude,
    );
    if (dist <= _arrivedThresholdMeters) {
      _geofenceTriggered = true;
      setState(() => _arrivedPromptVisible = true);
    }
  }

  Future<void> _confirmArrival() async {
    setState(() => _arrivedPromptVisible = false);
    await _updateStatus('arrived');
  }

  Future<void> _updateStatus(String status) async {
    await FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id)
        .update({'status': status});
  }

  /// On app restore, if the gig is already in 'working' status, pre-load the
  /// elapsed time from Firestore so the timer shows the correct running total.
  Future<void> _restoreElapsedIfWorking() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(widget.gigCollection)
          .doc(widget.gig.id)
          .get();
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      if ((data['status'] as String?) != 'working') return;
      final startTs = data['workStartedAt'] as Timestamp?;
      if (startTs == null) return;
      final alreadyElapsed = DateTime.now().difference(startTs.toDate());
      if (!mounted) return;
      setState(() => _elapsedOffset = alreadyElapsed);
      if (!_stopwatch.isRunning) _stopwatch.start();
    } catch (_) {}
  }

  /// Save workStartedAt + set status to 'working'.
  Future<void> _startWork() async {
    await FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id)
        .update({
      'status': 'working',
      'workStartedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stop timer, save duration fields + set status to 'task_complete'.
  Future<void> _completeWork() async {
    _stopwatch.stop();
    final total = _elapsedOffset + _stopwatch.elapsed;
    await FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id)
        .update({
      'status': 'task_complete',
      'durationSeconds': total.inSeconds,
      'workCompletedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Cancel gig — show reason form, save to Firestore, await admin review ──
  Future<void> _showCancelReasonDialog() async {
    final controller = TextEditingController();
    bool submitted = false;
    try {
      submitted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _CancelReasonDialog(controller: controller),
          ) ??
          false;
      if (!submitted || !mounted) return;
      final reason = controller.text.trim();
      if (reason.isEmpty) return;
      await FirebaseFirestore.instance
          .collection(widget.gigCollection)
          .doc(widget.gig.id)
          .update({
        'cancellation_reason': FieldValue.arrayUnion([
          {
            'reason': reason,
            'approved': null,
            'requestedBy': 'worker',
          }
        ]),
        'lastProgressStatus': _lastStatusString,
        'cancellationRequestedAt': FieldValue.serverTimestamp(),
        'status': 'cancellation_requested',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cancellation request submitted. Pending admin review.'),
            backgroundColor: Colors.orange,
          ),
        );
        // widget.onCancel();
      }
    } finally {
      controller.dispose();
    }
  }

  // ── Admin approved cancellation — notify and exit ─────────────────────────
  void _onAdminCancelled() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your cancellation request has been approved.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    widget.onCancel();
  }

  // ── Payment step — show confirmation sheet for worker to verify code ───────
  void _showWorkerPaymentConfirm() {
    if (!mounted) return;
    WorkerPaymentConfirmSheet.show(
      context: context,
      gigId: widget.gig.id,
      gigCollection: widget.gigCollection,
      budget: widget.gig.budget,
      hostName: widget.gig.hostName,
      onConfirmed: _onPaymentConfirmed,
    );
  }

  // Called by WorkerPaymentConfirmSheet after Firestore update succeeds.
  // WorkingUI owns the pop so it always closes the right route, then shows
  // the rating dialog without any race against the Firestore stream.
  void _onPaymentConfirmed() {
    if (!mounted || _ratingShown) return;
    _ratingShown = true;
    // Pop the payment sheet — this context owns the navigator that holds it.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    _showHostRatingAndComplete({
      'hostId': widget.gig.hostId,
      'hostName': widget.gig.hostName,
    });
  }

  // ── Show host rating dialog, then call onComplete ─────────────────────────
  Future<void> _showHostRatingAndComplete(Map<String, dynamic> data) async {
    final hostId = data['hostId'] as String? ?? '';
    final hostName = data['hostName'] as String? ?? 'Host';
    if (hostId.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HostRatingDialog(hostId: hostId, hostName: hostName),
      );
    }
    widget.onComplete();
  }

  // ── Fetch actual road route via OSRM ─────────────────────────────────────
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=polyline&steps=true',
      );
      final response = await http.get(uri);
      if (!mounted || response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final route   = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as String;
      final decoded  = PolylinePoints().decodePolyline(geometry);

      final distM   = (route['distance'] as num?)?.toDouble();
      final durS    = (route['duration'] as num?)?.toInt();

      final steps = <_RouteStep>[];
      final legs  = route['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final rawSteps = (legs[0] as Map<String, dynamic>)['steps'] as List? ?? [];
        for (final s in rawSteps) {
          final step  = s as Map<String, dynamic>;
          final dist  = (step['distance'] as num?)?.toDouble() ?? 0;
          steps.add(_RouteStep(
            instruction: _buildStepInstruction(step),
            icon: _iconForStepData(step),
            distanceM: dist,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _routePoints    = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
          _routeDistanceM = distM;
          _routeEtaSeconds = durS;
          _routeSteps     = steps;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    _locationSub?.cancel();
    _gigSub?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stepIndex = _GigStep.values.indexOf(_step);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress stepper ───────────────────────────────────────
            _ProgressStepper(currentIndex: stepIndex, isDark: isDark),

            // ── Scrollable body ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),

                    // ── Step-specific section ──────────────────────────
                    if (_step == _GigStep.navigating && !_arrivedPromptVisible)
                      _NavigatingSection(
                        gig: widget.gig,
                        workerLocation: _workerLocation,
                        routePoints: _routePoints,
                        routeDistanceM: _routeDistanceM,
                        routeEtaSeconds: _routeEtaSeconds,
                        routeSteps: _routeSteps,
                        divider: divider,
                      ),
                    if (_step == _GigStep.navigating && _arrivedPromptVisible) ...[
                      _StatusBanner(
                        icon: Icons.location_on_rounded,
                        color: green,
                        title: "You're at the Location!",
                        subtitle: 'Tap the button below to confirm your arrival.',
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        label: 'Confirm Arrival',
                        icon: Icons.location_on_rounded,
                        color: green,
                        onPressed: _confirmArrival,
                      ),
                    ],
                    if (_step == _GigStep.arrived)
                      _StatusBanner(
                        icon: Icons.location_on_rounded,
                        color: green,
                        title: "You've Arrived!",
                        subtitle: 'Tap Start Gig when you\'re ready to begin.',
                      ),
                    if (_step == _GigStep.working)
                      _TimerBanner(
                        elapsed: _fmt(_elapsed),
                        gigLabel: widget.gig.gigType == 'open'
                            ? 'Open Gig'
                            : widget.gig.gigType == 'offered'
                                ? 'Offered Gig'
                                : 'Quick Gig',
                      ),
                    if (_step == _GigStep.taskComplete)
                      _StatusBanner(
                        icon: Icons.hourglass_top_rounded,
                        color: kAmber,
                        title: 'Waiting for Host',
                        subtitle: 'The host will confirm your completion.',
                      ),
                    if (_step == _GigStep.payment)
                      _StatusBanner(
                        icon: Icons.payment_rounded,
                        color: kBlue,
                        title: 'Processing Payment',
                        subtitle: 'Your payment is being processed.',
                      ),
                    if (_step == _GigStep.completed)
                      _StatusBanner(
                        icon: Icons.verified_rounded,
                        color: green,
                        title: 'Gig Completed!',
                        subtitle:
                            '₱${widget.gig.budget.toStringAsFixed(0)} will be released to your wallet.',
                      ),

                    const SizedBox(height: 16),

                    if (_cancelPending) ...[
                      _StatusBanner(
                        icon: Icons.hourglass_top_rounded,
                        color: Colors.orange,
                        title: 'Cancellation Pending',
                        subtitle: 'Admin is reviewing your cancellation request.',
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Gig info card ──────────────────────────────────
                    _GigInfoCard(
                      gig: widget.gig,
                      step: _step,
                      cardColor: cardColor,
                      divider: divider,
                      isDark: isDark,
                      onSurface: onSurface,
                    ),

                    const SizedBox(height: 20),

                    // ── Primary action ─────────────────────────────────
                    if (_step == _GigStep.arrived)
                      _PrimaryButton(
                        label: 'Start Gig',
                        icon: Icons.play_arrow_rounded,
                        color: green,
                        onPressed: _startWork,
                      ),
                    if (_step == _GigStep.working)
                      _PrimaryButton(
                        label: 'Gig Complete',
                        icon: Icons.check_circle_outline_rounded,
                        color: green,
                        onPressed: _completeWork,
                      ),

                    // ── Cancel gig (only while still on the way / working) ─
                    if (!_cancelPending &&
                      (_step == _GigStep.navigating ||
                      _step == _GigStep.arrived ||
                      _step == _GigStep.working))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _showCancelReasonDialog,
                            icon: const Icon(Icons.cancel_outlined,
                                size: 20, color: Colors.redAccent),
                            label: const Text('Cancel Gig',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress stepper
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressStepper extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  const _ProgressStepper({required this.currentIndex, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_stepLabels.length, (i) {
            final isActive = i == currentIndex;
            final isDone = i < currentIndex;
            final dotColor = (isActive || isDone) ? green : kSub;
            final dotBg = isDone
                ? green
                : isActive
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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: dotBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (isActive || isDone)
                              ? green
                              : kSub.withValues(alpha: 0.3),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : _stepIcons[i],
                        size: 16,
                        color: isDone ? Colors.white : dotColor,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _stepLabels[i],
                      style: TextStyle(
                        fontSize: 9,
                        color: (isActive || isDone) ? green : kSub,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (i < _stepLabels.length - 1)
                  Container(
                    width: 22,
                    height: 1.5,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: i < currentIndex
                        ? green
                        : kSub.withValues(alpha: 0.25),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Navigating section — map with route line
// ─────────────────────────────────────────────────────────────────────────────
class _NavigatingSection extends StatefulWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final Color divider;
  final double? routeDistanceM;
  final int? routeEtaSeconds;
  final List<_RouteStep> routeSteps;
  const _NavigatingSection({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    required this.divider,
    this.routeDistanceM,
    this.routeEtaSeconds,
    this.routeSteps = const [],
  });

  @override
  State<_NavigatingSection> createState() => _NavigatingSectionState();
}

class _NavigatingSectionState extends State<_NavigatingSection> {
  GoogleMapController? _googleMapController;
  bool _useGoogleMaps = GmsAvailability.cachedIsAvailable;
  final _osmController = fm.MapController();
  bool _osmMapReady = false;

  @override
  void initState() {
    super.initState();
    GmsAvailability.isAvailable.then((v) {
      if (mounted) setState(() => _useGoogleMaps = v);
    });
  }

  @override
  void dispose() {
    _googleMapController?.dispose();
    _osmController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NavigatingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pan the camera when the worker location updates
    if (widget.workerLocation != null &&
        widget.workerLocation != oldWidget.workerLocation) {
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLng(widget.workerLocation!),
        );
      } else if (_osmMapReady) {
        _osmController.move(
          ll.LatLng(widget.workerLocation!.latitude, widget.workerLocation!.longitude),
          _osmController.camera.zoom,
        );
      }
    }
  }

  Future<void> _openNavigation() async {
    final dest = widget.gig.position;
    final uri  = Uri.parse(
      'geo:${dest.latitude},${dest.longitude}'
      '?q=${dest.latitude},${dest.longitude}(Gig+Location)',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Set<Marker> _buildGoogleMarkers() {
    final markers = <Marker>{};

    if (widget.workerLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('worker'),
          position: widget.workerLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    markers.add(
      Marker(
        markerId: const MarkerId('gig'),
        position: gigPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
    );

    return markers;
  }

  Widget _buildOsmMap() {
    final gigPos = ll.LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    final workerPos = widget.workerLocation != null
        ? ll.LatLng(widget.workerLocation!.latitude, widget.workerLocation!.longitude)
        : null;
    final osmMarkers = <fm.Marker>[];
    if (workerPos != null) {
      osmMarkers.add(fm.Marker(
        point: workerPos,
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.lightBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 14),
        ),
      ));
    }
    osmMarkers.add(fm.Marker(
      point: gigPos,
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Icon(Icons.work_rounded, color: Colors.white, size: 16),
      ),
    ));
    final routePoints = widget.routePoints
        .map((p) => ll.LatLng(p.latitude, p.longitude))
        .toList();
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: workerPos ?? gigPos,
        initialZoom: 14.0,
        onMapReady: () {
          if (mounted) setState(() => _osmMapReady = true);
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.mobile',
        ),
        if (routePoints.isNotEmpty)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(points: routePoints, color: kBlue, strokeWidth: 4),
            ],
          ),
        fm.MarkerLayer(markers: osmMarkers),
      ],
    );
  }

  Set<Polyline> _buildPolylines() {
    if (widget.routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: widget.routePoints,
        color: kBlue,
        width: 4,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    final initialTarget = widget.workerLocation ?? gigPos;
    final cardColor  = Theme.of(context).cardColor;
    final onSurface  = Theme.of(context).colorScheme.onSurface;
    final hasEta     = widget.routeDistanceM != null && widget.routeEtaSeconds != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBanner(
          icon: Icons.directions_rounded,
          color: kBlue,
          title: 'Navigating to Gig',
          subtitle:
              'Head to the gig location. Auto-detecting arrival within 40 m.',
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.divider),
            ),
            child: _useGoogleMaps
                ? GoogleMap(
                    onMapCreated: (controller) {
                      _googleMapController = controller;
                    },
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: 14.0,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: _buildGoogleMarkers(),
                    polylines: _buildPolylines(),
                  )
                : _buildOsmMap(),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Auto-detected at 40 m · Blue dot = you · Amber pin = gig · Blue line = route',
            style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 10),
          ),
        ),

        // ── ETA / distance row — shown for all users once route is ready ──
        if (hasEta) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBlue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, color: kBlue, size: 18),
                const SizedBox(width: 10),
                Text(
                  _fmtDist(widget.routeDistanceM!),
                  style: const TextStyle(
                    color: kBlue, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.access_time_rounded, color: kBlue, size: 16),
                const SizedBox(width: 6),
                Text(
                  'ETA ${_fmtEta(widget.routeEtaSeconds!)}',
                  style: const TextStyle(color: kBlue, fontSize: 13),
                ),
              ],
            ),
          ),
        ],

        // ── OSM-only: step-by-step directions + open navigation button ────
        if (!_useGoogleMaps) ...[
          if (widget.routeSteps.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DirectionsCard(
              steps: widget.routeSteps,
              cardColor: cardColor,
              onSurface: onSurface,
              divider: widget.divider,
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _openNavigation,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text(
                'Open Navigation App',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status banner (arrived / task_complete / payment / completed)
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.75), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Timer banner (working step)
// ─────────────────────────────────────────────────────────────────────────────
class _TimerBanner extends StatelessWidget {
  final String elapsed;
  final String gigLabel;
  const _TimerBanner({required this.elapsed, this.gigLabel = 'Quick Gig'});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: green.withValues(alpha: isDark ? 0.2 : 0.12),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: green.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.work_rounded, color: green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Currently Working',
                    style: TextStyle(
                        color: green,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('$gigLabel — Active',
                    style: const TextStyle(
                        color: Color(0xFF22C55E), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: green.withValues(alpha: 0.5)),
            ),
            child: Text(
              elapsed,
              style: const TextStyle(
                color: green,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig info card
// ─────────────────────────────────────────────────────────────────────────────
// ─── _GigInfoCard ────────────────────────────────────────────────────────────

// ─── _GigInfoCard ────────────────────────────────────────────────────────────

// ─── _GigInfoCard ────────────────────────────────────────────────────────────

class _GigInfoCard extends StatelessWidget {
  final GigMarkerData gig;
  final _GigStep step;
  final Color cardColor;
  final Color divider;
  final bool isDark;
  final Color onSurface;

  const _GigInfoCard({
    required this.gig,
    required this.step,
    required this.cardColor,
    required this.divider,
    required this.isDark,
    required this.onSurface,
  });

  (String, Color, Color) get _statusInfo {
    const green = Color(0xFF22C55E);
    const greenBg = Color(0xFFDCFCE7);
    const blueBg = Color(0xFFDBEAFE);
    const amberBg = Color(0xFFFEF3C7);
    switch (step) {
      case _GigStep.navigating:
        return ('Navigating', kBlue, blueBg);
      case _GigStep.arrived:
        return ('Arrived', green, greenBg);
      case _GigStep.working:
        return ('In Progress', green, greenBg);
      case _GigStep.taskComplete:
        return ('Task Complete', kAmber, amberBg);
      case _GigStep.payment:
        return ('Payment Pending', kBlue, blueBg);
      case _GigStep.completed:
        return ('Completed', green, greenBg);
    }
  }

  (Color, Color, IconData, String) get _gigTypeInfo {
    switch (gig.gigType) {
      case 'offered':
        return (
          const Color(0xFF8B5CF6),
          const Color(0xFFEDE9FE),
          Icons.send_rounded,
          'Offered gig',
        );
      case 'quick':
        return (
          kAmber,
          const Color(0xFFFEF3C7),
          Icons.flash_on_rounded,
          'Quick gig',
        );
      default:
        return (
          kBlue,
          const Color(0xFFDBEAFE),
          Icons.workspace_premium_outlined,
          'Open gig',
        );
    }
  }

  String get _initials {
    final parts = gig.hostName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return gig.hostName.isNotEmpty ? gig.hostName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusBg) = _statusInfo;
    final (gigColor, gigBg, gigIcon, gigLabel) = _gigTypeInfo;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: gigBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(gigIcon, color: gigColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gig.title,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _Pill(label: gigLabel, color: gigColor, bg: gigBg),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 0, thickness: 0.5, color: divider),

          // ── Info rows ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.attach_money_rounded,
                  label: 'Budget',
                  value: '₱${gig.budget.toStringAsFixed(0)}',
                  valueColor: kAmber,
                ),
                if (gig.address.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: gig.address,
                  ),
                _InfoRow(
                  icon: Icons.circle,
                  label: 'Status',
                  value: statusLabel,
                  valueColor: statusColor,
                  valueBg: statusBg,
                ),
              ],
            ),
          ),

          Divider(height: 0, thickness: 0.5, color: divider),

          // ── Host + call icons ─────────────────────────────────────────────
          if (gig.hostId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: gigBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials,
                      style: TextStyle(
                        color: gigColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gig.hostName.isNotEmpty ? gig.hostName : '—',
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Host',
                          style: TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.voice,
                  ),
                  const SizedBox(width: 4),
                  CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.video,
                  ),
                  const SizedBox(width: 4),
                  GigChatAction(
                    gigId: gig.id,
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── _InfoRow ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final Color? valueBg;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBg,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: kSub, size: 15),
            const SizedBox(width: 10),
            SizedBox(
              width: 54,
              child: Text(
                label,
                style: const TextStyle(color: kSub, fontSize: 12),
              ),
            ),
            // If valueBg is provided, wrap value in a pill
            valueBg != null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: valueBg,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: valueColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          value,
                          style: TextStyle(
                            color: valueColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: valueColor ??
                            Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ],
        ),
      );
}

// ─── _Pill ────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _Pill({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
// ─────────────────────────────────────────────────────────────────────────────
//  Primary action button
// ─────────────────────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          label: Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Directions card — collapsible step list shown on OSM devices
// ─────────────────────────────────────────────────────────────────────────────
class _DirectionsCard extends StatefulWidget {
  final List<_RouteStep> steps;
  final Color cardColor;
  final Color onSurface;
  final Color divider;
  const _DirectionsCard({
    required this.steps,
    required this.cardColor,
    required this.onSurface,
    required this.divider,
  });

  @override
  State<_DirectionsCard> createState() => _DirectionsCardState();
}

class _DirectionsCardState extends State<_DirectionsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visible = _expanded ? widget.steps : widget.steps.take(3).toList();
    return Container(
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.turn_right_rounded, color: kBlue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Turn-by-Turn Directions',
                      style: TextStyle(
                        color: widget.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: kSub, size: 20,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 0, thickness: 0.5, color: widget.divider),
          // Steps
          ...visible.asMap().entries.map((e) {
            final i    = e.key;
            final step = e.value;
            final isLast = i == visible.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: kBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(step.icon, color: kBlue, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.instruction,
                              style: TextStyle(
                                color: widget.onSurface, fontSize: 13),
                            ),
                            if (step.distanceM > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                _fmtDist(step.distanceM),
                                style: const TextStyle(color: kSub, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(height: 0, thickness: 0.5,
                      color: widget.divider, indent: 54),
              ],
            );
          }),
          // Show more / less
          if (widget.steps.length > 3)
            InkWell(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: widget.divider, width: 0.5)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Center(
                  child: Text(
                    _expanded
                        ? 'Show less'
                        : 'Show all ${widget.steps.length} steps',
                    style: const TextStyle(
                        color: kBlue, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Host Rating Dialog — shown after gig is completed (worker rates the host)
// ─────────────────────────────────────────────────────────────────────────────
class _HostRatingDialog extends StatefulWidget {
  final String hostId;
  final String hostName;

  const _HostRatingDialog({
    required this.hostId,
    required this.hostName,
  });

  @override
  State<_HostRatingDialog> createState() => _HostRatingDialogState();
}

class _HostRatingDialogState extends State<_HostRatingDialog> {
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
      final snap = await db.collection('users').doc(widget.hostId).get();
      final data = snap.data() ?? {};
      final currentRating =
          (data['ratingAsHost'] as num?)?.toDouble() ?? 5.0;
      final currentCount =
          (data['ratingAsHostCount'] as num?)?.toInt() ?? 0;
      final newCount = currentCount + 1;
      final newRating =
          ((currentRating * currentCount) + _selected) / newCount;
      await db.collection('users').doc(widget.hostId).update({
        'ratingAsHost': double.parse(newRating.toStringAsFixed(2)),
        'ratingAsHostCount': newCount,
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
            'Rate Your Host',
            style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was ${widget.hostName}?',
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
                fontWeight:
                    _selected > 0 ? FontWeight.bold : FontWeight.normal,
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
                  onPressed: (_selected == 0 || _submitting) ? null : _submit,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Cancel Reason Dialog — worker states reason; admin decides approval
// ─────────────────────────────────────────────────────────────────────────────
class _CancelReasonDialog extends StatefulWidget {
  final TextEditingController controller;
  const _CancelReasonDialog({required this.controller});

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined,
                color: Colors.redAccent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Request Cancellation',
            style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your request will be reviewed by an admin before the gig is cancelled.',
            style: TextStyle(color: kSub, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: onSurface, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Describe your reason for cancelling...',
              hintStyle:
                  TextStyle(color: kSub.withValues(alpha: 0.6), fontSize: 13),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Colors.redAccent, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child:
                      const Text('Go Back', style: TextStyle(color: kSub)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      _hasText ? () => Navigator.pop(context, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        Colors.redAccent.withValues(alpha: 0.35),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Submit Request',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
