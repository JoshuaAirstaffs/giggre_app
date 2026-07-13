import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import '../../../../core/utils/currency_formatter.dart';
import 'gig_map_section.dart';
import 'worker_payment_confirm_sheet.dart';
import '../../../../core/services/gms_availability.dart';
import '../../../../core/widgets/gig_completion_celebration.dart';

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

const _stepLabels = ['On the way', 'Arrived', 'Working', 'Done', 'Payment', 'Complete'];

// ─────────────────────────────────────────────────────────────────────────────
//  Active Gig design tokens — screen-scoped design system for this screen.
//  Structural colors (bg/card/border/text) flip with the app theme; brand and
//  status accents (blue/green/red) stay the same in both themes.
// ─────────────────────────────────────────────────────────────────────────────
Color _screenBg(bool isDark) => isDark ? kBg : const Color(0xFFF4F6FA);
Color _cardBg(bool isDark) => isDark ? kCard : Colors.white;
Color _cardBorder(bool isDark) => isDark ? kBorder : const Color(0xFFE4E9F0);
const double _kCardRadius = 16.0;
const Color _kPrimaryBlue = Color(0xFF2B6FB5);
const Color _kDarkBlue = Color(0xFF1F4D80);
Color _textPrimary(bool isDark) => isDark ? Colors.white : const Color(0xFF17263D);
Color _textSecondary(bool isDark) => isDark ? const Color(0xFFB6C2D1) : const Color(0xFF5A6778);
Color _textMuted(bool isDark) => isDark ? kSub : const Color(0xFF94A0B0);
Color _textDisabled(bool isDark) => isDark ? const Color(0xFF64748B) : const Color(0xFFB7C0CD);
const Color _kSuccessGreen = Color(0xFF2E9E6B);
const Color _kDestructiveRed = Color(0xFFE5484D);
Color _destructiveBorder(bool isDark) =>
    isDark ? Colors.redAccent.withValues(alpha: 0.35) : const Color(0xFFF5C6C8);
Color _dividerColor(bool isDark) => isDark ? kBorder : const Color(0xFFEEF2F7);
Color _trackBg(bool isDark) => isDark ? const Color(0xFF334155) : const Color(0xFFE4E9F0);

// Title/body copy for the progress card's instruction block — same 6-status
// source of truth as _stepFromStatus above; no new states invented.
class _StepCopy {
  final String title;
  final String body;
  const _StepCopy(this.title, this.body);
}

_StepCopy _instructionFor(_GigStep step, GigMarkerData gig) {
  switch (step) {
    case _GigStep.navigating:
      return const _StepCopy(
        'Head to the gig location',
        "We'll detect your arrival automatically within 40 m — no need to check in.",
      );
    case _GigStep.arrived:
      return const _StepCopy(
        "You've arrived!",
        'Waiting for the host to confirm and start the gig.',
      );
    case _GigStep.working:
      return const _StepCopy(
        'Gig in progress',
        'The host will mark the work as done when finished.',
      );
    case _GigStep.taskComplete:
      return const _StepCopy(
        'Work complete',
        'Waiting for the host to process your payment.',
      );
    case _GigStep.payment:
      return _StepCopy(
        'Payment processing',
        '${CurrencyFormatter.format(gig.budget, gig.currencyCode)} is on its way to you.',
      );
    case _GigStep.completed:
      return const _StepCopy(
        'All done — great work!',
        'This gig is complete. Rate your host below.',
      );
  }
}

// Display-only address cleanup — collapses immediate consecutive duplicate
// comma-separated parts (e.g. "Foo St, Foo St, City" -> "Foo St, City").
// Never writes back to Firestore; the stored value is untouched.
String _dedupedAddress(String address) {
  final parts = address
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final deduped = <String>[];
  for (final p in parts) {
    if (deduped.isEmpty || deduped.last.toLowerCase() != p.toLowerCase()) {
      deduped.add(p);
    }
  }
  return deduped.join(', ');
}

// ─────────────────────────────────────────────────────────────────────────────
//  Route step model + helpers (used by _fetchRoute)
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
  final _arrivedSoundPlayer = AudioPlayer();
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
  static const _arrivedThresholdMeters = 40.0;

  // Actual road route
  List<LatLng> _routePoints = [];
  LatLng? _lastRouteFetch;
  double? _routeDistanceM;
  int? _routeEtaSeconds;
  List<_RouteStep> _routeSteps = [];

  // Firestore live listener
  StreamSubscription? _gigSub;

  // Location status
  String? _locationWarning;
  StreamSubscription<ServiceStatus>? _locationServiceSub;

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
      if (!enabled) {
        if (mounted) setState(() => _locationWarning = 'Location is turned off. Tracking is paused.');
        _locationServiceSub?.cancel();
        _locationServiceSub = Geolocator.getServiceStatusStream().listen((status) {
          if (!mounted) return;
          if (status == ServiceStatus.enabled) {
            _locationServiceSub?.cancel();
            _locationServiceSub = null;
            setState(() => _locationWarning = null);
            _startLocation();
          }
        });
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationWarning = perm == LocationPermission.deniedForever
              ? 'Location permanently denied. Enable in app settings.'
              : 'Location permission denied. Tracking is paused.');
        }
        return;
      }
      if (mounted) setState(() => _locationWarning = null);
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
      }, onError: (e) {
        debugPrint('[WorkingUI] location stream error: $e');
        if (!mounted) return;
        if (e is LocationServiceDisabledException) {
          setState(() => _locationWarning = 'Location turned off. Tracking is paused.');
          _startLocation();
        } else if (e is PermissionDefinitionsNotFoundException) {
          setState(() => _locationWarning = 'Location permission revoked. Tracking is paused.');
        } else {
          setState(() => _locationWarning = 'Location error. Tracking may be interrupted.');
        }
      });
    } catch (e) {
      debugPrint('[WorkingUI] _startLocation error: $e');
      if (mounted) setState(() => _locationWarning = 'Could not start location tracking.');
    }
  }

  void _checkGeofence(Position pos) {
    if (_step != _GigStep.navigating) return;
    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      widget.gig.position.latitude, widget.gig.position.longitude,
    );
    final withinRange = dist <= _arrivedThresholdMeters;
    // Reactive, not a one-shot latch — walking back out of range hides the
    // prompt again, and walking back in shows it again.
    if (withinRange != _arrivedPromptVisible) {
      setState(() => _arrivedPromptVisible = withinRange);
      if (withinRange) {
        _arrivedSoundPlayer.play(AssetSource('sounds/gig_sound.mp3'));
      }
    }
  }

  Future<void> _confirmArrival() async {
    setState(() => _arrivedPromptVisible = false);
    await FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id)
        .update({
      'status': 'arrived',
      'arrivedAt': FieldValue.serverTimestamp(),
    });
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
      currencyCode: widget.gig.currencyCode,
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
    // Wait a frame so the sheet's pop transition fully settles before pushing
    // the celebration dialog on the same navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showThankYouThenRating();
    });
  }

  Future<void> _showThankYouThenRating() async {
    if (mounted) {
      try {
        await GigCompletionCelebration.show(
          context: context,
          title: 'Thank You!',
          subtitle: 'Payment received — great work getting this gig done!',
          icon: Icons.celebration_rounded,
        );
      } catch (e, st) {
        debugPrint('[WorkingUI] celebration dialog error: $e\n$st');
      }
    }
    if (!mounted) return;
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
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
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
    _locationServiceSub?.cancel();
    _gigSub?.cancel();
    _arrivedSoundPlayer.dispose();
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
    final stepIndex = _GigStep.values.indexOf(_step);
    final copy = _instructionFor(_step, widget.gig);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _screenBg(isDark),
      body: SafeArea(
        child: Column(
          children: [
            _ActiveGigHeader(
              statusLabel: _stepLabels[stepIndex],
              onBack: () => Navigator.of(context).maybePop(),
            ),

            // ── Location warning ───────────────────────────────────────
            if (_locationWarning != null)
              Container(
                width: double.infinity,
                color: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationWarning!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    if (_locationWarning!.contains('settings'))
                      TextButton(
                        onPressed: () => Geolocator.openAppSettings(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                  ],
                ),
              ),

            // ── Scrollable body ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ActiveGigProgressCard(
                      stepIndex: stepIndex,
                      title: copy.title,
                      body: copy.body,
                      elapsed: _step == _GigStep.working ? _fmt(_elapsed) : null,
                      arrivedPromptVisible: _arrivedPromptVisible,
                      onConfirmArrival: _confirmArrival,
                      isCancelPending: _cancelPending,
                      showStartGig: _step == _GigStep.arrived,
                      onStartGig: _startWork,
                      showGigComplete: _step == _GigStep.working,
                      onGigComplete: _completeWork,
                    ),
                    const SizedBox(height: 16),

                    _ActiveGigMapCard(
                      gig: widget.gig,
                      workerLocation: _workerLocation,
                      routePoints: _routePoints,
                      routeDistanceM: _routeDistanceM,
                    ),
                    const SizedBox(height: 16),

                    _GigHostCard(gig: widget.gig),

                    const SizedBox(height: 20),

                    // ── Cancel gig (only while still on the way / working) ─
                    if (!_cancelPending &&
                        (_step == _GigStep.navigating ||
                            _step == _GigStep.arrived ||
                            _step == _GigStep.working))
                      _CancelGigSection(onPressed: _showCancelReasonDialog),

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
//  Header — compact gradient app bar
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveGigHeader extends StatelessWidget {
  final String statusLabel;
  final VoidCallback onBack;
  const _ActiveGigHeader({required this.statusLabel, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimaryBlue, _kDarkBlue],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      padding: const EdgeInsets.only(left: 4, right: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          const Text(
            'Active Gig',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '●  $statusLabel',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  6-step horizontal tracker
// ─────────────────────────────────────────────────────────────────────────────
class _StepTracker extends StatelessWidget {
  final int currentIndex;
  const _StepTracker({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final total = _stepLabels.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = constraints.maxWidth / total;
        final fillFraction =
            total <= 1 ? 1.0 : currentIndex / (total - 1);
        return Column(
          children: [
            SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: segment / 2,
                    right: segment / 2,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: _trackBg(isDark),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: segment / 2,
                    right: segment / 2,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fillFraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: _kPrimaryBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(total, (i) {
                      return Expanded(
                        child: Center(
                          child: _StepDot(
                            isDone: i < currentIndex,
                            isCurrent: i == currentIndex,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: List.generate(total, (i) {
                final isCurrent = i == currentIndex;
                final isDone = i < currentIndex;
                final color = isCurrent
                    ? _kPrimaryBlue
                    : isDone
                        ? _textSecondary(isDark)
                        : _textDisabled(isDark);
                return Expanded(
                  child: Text(
                    _stepLabels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      color: color,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool isDone;
  final bool isCurrent;
  const _StepDot({required this.isDone, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isCurrent) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: _kPrimaryBlue.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _kPrimaryBlue,
            shape: BoxShape.circle,
            border: Border.all(color: _cardBg(isDark), width: 3),
          ),
        ),
      );
    }
    if (isDone) {
      return Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
            color: _kPrimaryBlue, shape: BoxShape.circle),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        shape: BoxShape.circle,
        border: Border.all(color: _cardBorder(isDark), width: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress card — step tracker + instruction block (single source of truth:
//  the same _step/stepIndex the header chip and tracker fill derive from)
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveGigProgressCard extends StatelessWidget {
  final int stepIndex;
  final String title;
  final String body;
  final String? elapsed;
  final bool arrivedPromptVisible;
  final VoidCallback onConfirmArrival;
  final bool isCancelPending;
  final bool showStartGig;
  final VoidCallback onStartGig;
  final bool showGigComplete;
  final VoidCallback onGigComplete;

  const _ActiveGigProgressCard({
    required this.stepIndex,
    required this.title,
    required this.body,
    this.elapsed,
    required this.arrivedPromptVisible,
    required this.onConfirmArrival,
    required this.isCancelPending,
    required this.showStartGig,
    required this.onStartGig,
    required this.showGigComplete,
    required this.onGigComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _cardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: _StepTracker(currentIndex: stepIndex),
          ),
          Divider(height: 0, thickness: 1, color: _dividerColor(isDark)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: _textPrimary(isDark),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (elapsed != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kSuccessGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          elapsed!,
                          style: const TextStyle(
                            color: _kSuccessGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                      color: _textMuted(isDark), fontSize: 11, height: 1.4),
                ),
                if (arrivedPromptVisible) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kSuccessGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _kSuccessGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: _kSuccessGreen, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "You're at the location — confirm your arrival.",
                            style: TextStyle(
                                color: _kSuccessGreen,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onConfirmArrival,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kSuccessGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Confirm Arrival',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                if (isCancelPending) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAmber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded,
                            color: kAmber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cancellation pending — admin is reviewing your request.',
                            style: TextStyle(
                                color: kAmber,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (showStartGig) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onStartGig,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Start Gig',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
                if (showGigComplete) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onGigComplete,
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 20),
                      label: const Text('Gig Complete',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kSuccessGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Map card — reuses _NavMapCore's existing GoogleMap/OSM instance & config;
//  only the surrounding container styling and overlays are new.
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveGigMapCard extends StatefulWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final double? routeDistanceM;

  const _ActiveGigMapCard({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    this.routeDistanceM,
  });

  @override
  State<_ActiveGigMapCard> createState() => _ActiveGigMapCardState();
}

class _ActiveGigMapCardState extends State<_ActiveGigMapCard> {
  // Unchanged from the previous _NavigatingSectionState — tapping the
  // destination marker still opens the same in-app-browser directions link.
  Future<void> _openNavigation() async {
    final dest = widget.gig.position;
    final dirUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${dest.latitude},${dest.longitude}'
      '&travelmode=driving',
    );
    await launchUrl(dirUri, mode: LaunchMode.inAppBrowserView);
  }

  // Unchanged from the previous _NavigatingSectionState — same fullscreen
  // map dialog, reusing the same _MapRoundButton close control.
  void _openFullScreenMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _NavMapCore(
                    gig: widget.gig,
                    workerLocation: widget.workerLocation,
                    routePoints: widget.routePoints,
                    onDestinationTap: _openNavigation,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _MapRoundButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: Container(
        height: 312,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: _cardBorder(isDark)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: _NavMapCore(
                gig: widget.gig,
                workerLocation: widget.workerLocation,
                routePoints: widget.routePoints,
                onDestinationTap: _openNavigation,
                onExpand: _openFullScreenMap,
                // Smaller than the default 60 so the fixed padding doesn't
                // eat too much of the frame and force excess zoom-out.
                fitPadding: 20,
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: _MapInfoChip(distanceM: widget.routeDistanceM),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapInfoChip extends StatelessWidget {
  final double? distanceM;
  const _MapInfoChip({this.distanceM});

  @override
  Widget build(BuildContext context) {
    final distText = distanceM != null ? ' · ${_fmtDist(distanceM!)}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: _kPrimaryBlue, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text('You',
              style: TextStyle(color: Color(0xFF5A6778), fontSize: 9)),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text('Gig  - - Route$distText',
              style: const TextStyle(color: Color(0xFF5A6778), fontSize: 9)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Navigation map core — renders the Google/OSM map with zoom + expand controls.
//  Used both embedded (fixed height, rounded card) and full screen (height: null).
// ─────────────────────────────────────────────────────────────────────────────
class _NavMapCore extends StatefulWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final Color? divider;
  final double? height;
  final VoidCallback? onExpand;
  final VoidCallback? onDestinationTap;
  final double fitPadding;

  const _NavMapCore({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    this.divider,
    this.height,
    this.onExpand,
    this.onDestinationTap,
    this.fitPadding = 60,
  });

  @override
  State<_NavMapCore> createState() => _NavMapCoreState();
}

class _NavMapCoreState extends State<_NavMapCore> {
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
  void didUpdateWidget(_NavMapCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Also re-fit when the route arrives/changes (it's fetched async, often
    // slightly after the location update that triggered this rebuild), so
    // the polyline itself is never left clipped outside the fitted bounds.
    if (widget.workerLocation != oldWidget.workerLocation ||
        widget.routePoints.length != oldWidget.routePoints.length) {
      _animateToFit();
    }
  }

  // Fits the camera so both the worker's live position and the gig
  // destination stay in view, instead of a fixed zoom that may crop one out.
  void _animateToFit() {
    final worker = widget.workerLocation;
    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    if (worker == null) {
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(gigPos, 15.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(ll.LatLng(gigPos.latitude, gigPos.longitude), 15.0);
      }
      return;
    }

    // Fit every point along the route too, not just the two endpoints —
    // otherwise a curvy road can bow outside the bounds and get clipped.
    var swLat = min(gigPos.latitude, worker.latitude);
    var swLng = min(gigPos.longitude, worker.longitude);
    var neLat = max(gigPos.latitude, worker.latitude);
    var neLng = max(gigPos.longitude, worker.longitude);
    for (final p in widget.routePoints) {
      swLat = min(swLat, p.latitude);
      swLng = min(swLng, p.longitude);
      neLat = max(neLat, p.latitude);
      neLng = max(neLng, p.longitude);
    }

    if (_useGoogleMaps) {
      _googleMapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(swLat, swLng),
            northeast: LatLng(neLat, neLng),
          ),
          widget.fitPadding,
        ),
      );
    } else if (_osmMapReady) {
      _osmController.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds(
            ll.LatLng(swLat, swLng),
            ll.LatLng(neLat, neLng),
          ),
          padding: EdgeInsets.all(widget.fitPadding),
        ),
      );
    }
  }

  Set<Marker> _buildGoogleMarkers() {
    // Worker location is shown by the native blue dot (myLocationEnabled: true).
    // Only the gig destination needs a pin.
    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    return {
      Marker(
        markerId: const MarkerId('gig'),
        position: gigPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        // No custom onTap — tapping shows the info window, and Android's
        // native map toolbar (Directions / Open in Google Maps) appears
        // alongside it automatically since mapToolbarEnabled defaults to true.
        infoWindow: InfoWindow(
          title: widget.gig.title.isNotEmpty ? widget.gig.title : 'Gig Location',
          snippet: 'Tap for directions',
        ),
      ),
    };
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
      child: GestureDetector(
        onTap: widget.onDestinationTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.work_rounded, color: Colors.white, size: 16),
        ),
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
          _animateToFit();
        },
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.pinchZoom |
              fm.InteractiveFlag.doubleTapZoom |
              fm.InteractiveFlag.drag,
        ),
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

  Widget _buildControls() {
    if (widget.onExpand == null) return const SizedBox.shrink();
    return Positioned(
      left: 10,
      bottom: 10,
      child: _MapRoundButton(
        icon: Icons.fullscreen_rounded,
        onTap: widget.onExpand!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    final initialTarget = widget.workerLocation ?? gigPos;

    final mapWidget = _useGoogleMaps
        ? GoogleMap(
            onMapCreated: (controller) {
              _googleMapController = controller;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _animateToFit();
              });
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
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer()),
            },
          )
        : _buildOsmMap();

    final stack = Stack(
      children: [
        Positioned.fill(child: mapWidget),
        _buildControls(),
      ],
    );

    if (widget.height == null) return stack;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: widget.divider != null ? Border.all(color: widget.divider!) : null,
        ),
        child: stack,
      ),
    );
  }
}

class _MapRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapRoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig + host card
// ─────────────────────────────────────────────────────────────────────────────
class _GigHostCard extends StatelessWidget {
  final GigMarkerData gig;
  const _GigHostCard({required this.gig});

  String get _initials {
    final parts = gig.hostName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return gig.hostName.isNotEmpty ? gig.hostName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: _cardBg(isDark),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _cardBorder(isDark)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  gig.title,
                  style: TextStyle(
                    color: _textPrimary(isDark),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              RichText(
                textAlign: TextAlign.right,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: CurrencyFormatter.format(gig.budget, gig.currencyCode),
                      style: const TextStyle(
                        color: _kPrimaryBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: ' / gig',
                      style: TextStyle(
                        color: _textMuted(isDark),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (gig.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined,
                    color: _textMuted(isDark), size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _dedupedAddress(gig.address),
                    style: TextStyle(color: _textMuted(isDark), fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 0, thickness: 1, color: _dividerColor(isDark)),
          const SizedBox(height: 14),
          if (gig.hostId.isNotEmpty)
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kPrimaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: _kPrimaryBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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
                          color: _textPrimary(isDark),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('Your host',
                          style: TextStyle(color: _textMuted(isDark), fontSize: 10.5)),
                    ],
                  ),
                ),
                _HostActionCircle(
                  bg: _kPrimaryBlue.withValues(alpha: 0.12),
                  child: CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.voice,
                    iconColor: _kPrimaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                _HostActionCircle(
                  bg: _kPrimaryBlue.withValues(alpha: 0.12),
                  child: CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.video,
                    iconColor: _kPrimaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                _HostActionCircle(
                  bg: _kPrimaryBlue,
                  child: GigChatAction(
                    gigId: gig.id,
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    iconColor: Colors.white,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HostActionCircle extends StatelessWidget {
  final Color bg;
  final Widget child;
  const _HostActionCircle({required this.bg, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cancel gig section
// ─────────────────────────────────────────────────────────────────────────────
class _CancelGigSection extends StatelessWidget {
  final VoidCallback onPressed;
  const _CancelGigSection({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: _kDestructiveRed),
            label: const Text(
              'Cancel gig',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kDestructiveRed),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: _cardBg(isDark),
              side: BorderSide(color: _destructiveBorder(isDark), width: 1),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Cancelling after being selected may affect your worker rating',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textDisabled(isDark), fontSize: 9.5),
        ),
      ],
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
