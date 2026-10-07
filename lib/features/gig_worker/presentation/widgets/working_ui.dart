import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../../../../core/theme/map_style.dart';
import '../../../../core/utils/cancellation_request.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'gig_map_section.dart';
import 'worker_payment_confirm_sheet.dart';
import '../../../../core/services/gms_availability.dart';
import '../../../../core/widgets/gig_completion_celebration.dart';
import '../../../../core/services/rating_service.dart';
import '../../../../core/widgets/rating_dialog.dart';
import '../../../gig_shared/active_gig_theme.dart';
import '../../../gig_shared/active_gig_step.dart';
import '../../../gig_shared/active_gig_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Route step model + helpers (used by _fetchRoute)
// ─────────────────────────────────────────────────────────────────────────────
class _RouteStep {
  final String instruction;
  final IconData icon;
  final double distanceM;
  const _RouteStep({
    required this.instruction,
    required this.icon,
    required this.distanceM,
  });
}

String _buildStepInstruction(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
  final type = maneuver['type'] as String? ?? '';
  final modifier = maneuver['modifier'] as String? ?? '';
  final name = (step['name'] as String? ?? '').trim();
  final onto = name.isNotEmpty ? ' onto $name' : '';
  switch (type) {
    case 'depart':
      return 'Head out${onto.isNotEmpty ? onto : ''}';
    case 'arrive':
      return 'Arrive at destination';
    case 'turn':
      return 'Turn ${_stepDir(modifier)}$onto';
    case 'new name':
    case 'continue':
      return 'Continue${onto.isEmpty ? ' straight' : onto}';
    case 'merge':
      return 'Merge ${_stepDir(modifier)}$onto';
    case 'on ramp':
      return 'Take the ramp ${_stepDir(modifier)}';
    case 'off ramp':
      return 'Take exit${onto.isNotEmpty ? onto : ''}';
    case 'fork':
      return 'Keep ${_stepDir(modifier)} at the fork';
    case 'end of road':
      return 'Turn ${_stepDir(modifier)} at end of road';
    case 'roundabout':
    case 'rotary':
      {
        final exit = maneuver['exit'] as int?;
        return exit != null
            ? 'Take exit $exit at roundabout'
            : 'Enter the roundabout';
      }
    default:
      return name.isNotEmpty ? 'Continue on $name' : 'Continue';
  }
}

String _stepDir(String modifier) {
  switch (modifier) {
    case 'uturn':
      return 'around';
    case 'sharp right':
      return 'sharp right';
    case 'right':
      return 'right';
    case 'slight right':
      return 'slightly right';
    case 'slight left':
      return 'slightly left';
    case 'left':
      return 'left';
    case 'sharp left':
      return 'sharp left';
    default:
      return 'straight';
  }
}

IconData _iconForStepData(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
  final type = maneuver['type'] as String? ?? '';
  final modifier = maneuver['modifier'] as String? ?? '';
  switch (type) {
    case 'depart':
      return Icons.navigation_rounded;
    case 'arrive':
      return Icons.location_on_rounded;
    case 'roundabout':
    case 'rotary':
      return Icons.roundabout_right_rounded;
    case 'merge':
      return Icons.merge_rounded;
    case 'on ramp':
    case 'off ramp':
      return Icons.ramp_right_rounded;
    default:
      if (modifier.contains('left')) return Icons.turn_left_rounded;
      if (modifier.contains('right')) return Icons.turn_right_rounded;
      return Icons.straight_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Working UI — full-screen view shown when a quick gig is active
// ─────────────────────────────────────────────────────────────────────────────
class WorkingUI extends StatefulWidget {
  final GigMarkerData gig;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  // Fired right after the cancellation *request* is submitted (before admin
  // approval) — lets the caller take the worker back to the dashboard
  // immediately. Distinct from onCancel, which only fires once an admin
  // actually approves the request (see _onAdminCancelled) and runs the
  // real cleanup (freeing the slot, backfill search, etc.) — firing that
  // early would wrongly tear down a gig that's still awaiting review.
  final VoidCallback? onCancellationRequested;
  final String gigCollection;

  const WorkingUI({
    super.key,
    required this.gig,
    required this.onComplete,
    required this.onCancel,
    this.onCancellationRequested,
    this.gigCollection = 'quick_gigs',
  });

  @override
  State<WorkingUI> createState() => _WorkingUIState();
}

class _WorkingUIState extends State<WorkingUI> {
  GigStep _step = GigStep.navigating;

  GigStep _lastActiveStep = GigStep.navigating;
  String _lastStatusString = 'navigating';
  bool _cancelPending = false;
  // A cancellation can be asked for by either side, so the pending notice has
  // to know which — otherwise a host-initiated request reads to the worker as
  // "admin is reviewing your request".
  bool _cancelRequestedByHost = false;
  // Whether this listener has seen a live (non-pending) status yet — see the
  // lastProgressStatus fallback in _listenGig.
  bool _sawActiveStatus = false;

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
  int? _routeEtaSeconds;
  List<_RouteStep> _routeSteps = [];

  // Firestore live listener
  StreamSubscription? _gigSub;

  // Draggable bottom sheet (map underneath) — dragged down to _sheetMin
  // reveals the map full-screen; the floating arrow-up button then
  // animates it back to _sheetInitial.
  final _sheetController = DraggableScrollableController();
  bool _sheetCollapsed = false;
  static const _sheetMin = 0.14;
  static const _sheetInitial = 0.55;

  // Location status
  String? _locationWarning;
  StreamSubscription<ServiceStatus>? _locationServiceSub;

  // On a multi-worker gig, this worker's own `workers/{uid}` subcollection
  // doc is the write/listen target instead of the gig doc — every other
  // write in this widget goes through _targetRef so one worker's progress
  // never touches another worker's slot on the same gig. Null (legacy
  // single-worker gigs, or quick/offered gigs not yet on this model) falls
  // back to the gig doc unchanged.
  String? _slotWorkerId;

  DocumentReference<Map<String, dynamic>> get _targetRef {
    final gigRef = FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gig.id);
    final slotId = _slotWorkerId;
    return slotId == null ? gigRef : gigRef.collection('workers').doc(slotId);
  }

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stopwatch.isRunning) {
        setState(() => _elapsed = _elapsedOffset + _stopwatch.elapsed);
      }
    });
    _sheetController.addListener(_onSheetSizeChanged);
    _init();
  }

  void _onSheetSizeChanged() {
    if (!_sheetController.isAttached) return;
    final collapsed = _sheetController.size <= _sheetMin + 0.02;
    if (collapsed != _sheetCollapsed) {
      setState(() => _sheetCollapsed = collapsed);
    }
  }

  void _toggleSheet() {
    _sheetController.animateTo(
      _sheetCollapsed ? _sheetInitial : _sheetMin,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _init() async {
    await _resolveSlotRef();
    if (!mounted) return;
    _listenGig();
    _startLocation();
    _restoreElapsedIfWorking();
  }

  Future<void> _resolveSlotRef() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(widget.gigCollection)
          .doc(widget.gig.id)
          .collection('workers')
          .doc(uid)
          .get();
      if (snap.exists && mounted) setState(() => _slotWorkerId = uid);
    } catch (_) {}
  }

  // ── Firestore listener ────────────────────────────────────────────────────
  void _listenGig() {
    _gigSub = _targetRef.snapshots().listen((snap) {
      if (!mounted || !snap.exists) return;

      final status = snap.data()?['status'] as String? ?? 'navigating';

      if (status == 'cancelled' && !_cancelledHandled) {
        _cancelledHandled = true;
        // Read the requester off this snapshot rather than _cancelRequestedByHost:
        // a gig can go straight to 'cancelled' without this listener ever
        // seeing the pending state (app restored after approval, say).
        final byHost = isHostRequestedCancellation(snap.data());
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _onAdminCancelled(byHost: byHost),
        );
        return;
      }

      final isCancelPending = status == 'cancellation_requested';
      final cancelRequestedByHost =
          isCancelPending && isHostRequestedCancellation(snap.data());

      // A pending request freezes the doc's status, so the tracker holds the
      // step the gig was on. If this listener started up mid-request (the
      // host asked while the screen was closed) there's no in-memory step to
      // hold — fall back to the lastProgressStatus whoever requested it
      // stamped, rather than resetting the worker to 'On the way'.
      final newStep = isCancelPending
          ? (_sawActiveStatus
                ? _lastActiveStep
                : gigStepFromStatus(_frozenStatus(snap.data())))
          : gigStepFromStatus(status);

      if (!isCancelPending) {
        _sawActiveStatus = true;
        _lastActiveStep = newStep;
        _lastStatusString = status;
      }

      if (newStep != _step ||
          isCancelPending != _cancelPending ||
          cancelRequestedByHost != _cancelRequestedByHost) {
        setState(() {
          _step = newStep;
          _cancelPending = isCancelPending;
          _cancelRequestedByHost = cancelRequestedByHost;
        });
      }

      if (newStep == GigStep.working && !_stopwatch.isRunning) {
        _stopwatch.start();
      }

      if (newStep == GigStep.payment && !_paymentConfirmShown) {
        _paymentConfirmShown = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showWorkerPaymentConfirm(),
        );
      }

      if (newStep == GigStep.completed && !_ratingShown) {
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
        if (mounted)
          setState(
            () => _locationWarning =
                'Location is turned off. Tracking is paused.',
          );
        _locationServiceSub?.cancel();
        _locationServiceSub = Geolocator.getServiceStatusStream().listen((
          status,
        ) {
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
          setState(
            () => _locationWarning = perm == LocationPermission.deniedForever
                ? 'Location permanently denied. Enable in app settings.'
                : 'Location permission denied. Tracking is paused.',
          );
        }
        return;
      }
      if (mounted) setState(() => _locationWarning = null);
      _locationSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (pos) {
              if (!mounted) return;
              final loc = LatLng(pos.latitude, pos.longitude);
              setState(() => _workerLocation = loc);
              _checkGeofence(pos);
              // Re-fetch route only when navigating and moved >30 m from last fetch
              if (_step == GigStep.navigating) {
                // Persist location to Firestore so host can track worker in real-time
                _targetRef
                    .update({
                      'workerLocation': GeoPoint(pos.latitude, pos.longitude),
                    })
                    .catchError((_) {});

                final gigPos = LatLng(
                  widget.gig.position.latitude,
                  widget.gig.position.longitude,
                );
                final shouldFetch =
                    _lastRouteFetch == null ||
                    Geolocator.distanceBetween(
                          _lastRouteFetch!.latitude,
                          _lastRouteFetch!.longitude,
                          loc.latitude,
                          loc.longitude,
                        ) >
                        30;
                if (shouldFetch) {
                  _lastRouteFetch = loc;
                  _fetchRoute(loc, gigPos);
                }
              }
            },
            onError: (e) {
              debugPrint('[WorkingUI] location stream error: $e');
              if (!mounted) return;
              if (e is LocationServiceDisabledException) {
                setState(
                  () => _locationWarning =
                      'Location turned off. Tracking is paused.',
                );
                _startLocation();
              } else if (e is PermissionDefinitionsNotFoundException) {
                setState(
                  () => _locationWarning =
                      'Location permission revoked. Tracking is paused.',
                );
              } else {
                setState(
                  () => _locationWarning =
                      'Location error. Tracking may be interrupted.',
                );
              }
            },
          );
    } catch (e) {
      debugPrint('[WorkingUI] _startLocation error: $e');
      if (mounted)
        setState(() => _locationWarning = 'Could not start location tracking.');
    }
  }

  void _checkGeofence(Position pos) {
    if (_step != GigStep.navigating) return;
    final dist = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.gig.position.latitude,
      widget.gig.position.longitude,
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
    await _targetRef.update({
      'status': 'arrived',
      'arrivedAt': FieldValue.serverTimestamp(),
    });
  }

  /// On app restore, if the gig is already in 'working' status, pre-load the
  /// elapsed time from Firestore so the timer shows the correct running total.
  // The step a doc is really on: while a cancellation is pending its status
  // reads 'cancellation_requested', and the step it froze at lives in
  // lastProgressStatus (written by every requester — see
  // hostCancellationRequestUpdate and _showCancelReasonDialog below).
  static String _frozenStatus(Map<String, dynamic>? data) {
    final status = data?['status'] as String? ?? 'navigating';
    if (status != 'cancellation_requested') return status;
    return data?['lastProgressStatus'] as String? ?? 'working';
  }

  Future<void> _restoreElapsedIfWorking() async {
    try {
      final snap = await _targetRef.get();
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      // Counts a gig frozen mid-work by a pending cancellation as working —
      // otherwise the stopwatch restarts from zero on that screen.
      if (_frozenStatus(data) != 'working') return;
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
    await _targetRef.update({
      'status': 'working',
      'workStartedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stop timer, save duration fields + set status to 'task_complete'.
  Future<void> _completeWork() async {
    _stopwatch.stop();
    final total = _elapsedOffset + _stopwatch.elapsed;
    await _targetRef.update({
      'status': 'task_complete',
      'durationSeconds': total.inSeconds,
      'workCompletedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Cancel gig — show reason form, save to Firestore, await admin review ──
  Future<void> _showCancelReasonDialog() async {
    final controller = TextEditingController();
    try {
      final submitted =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _CancelReasonDialog(controller: controller),
          ) ??
          false;
      if (!submitted || !mounted) return;
      final reason = controller.text.trim();
      if (reason.isEmpty) return;
      await _targetRef.update({
        'cancellation_reason': FieldValue.arrayUnion([
          {'reason': reason, 'approved': null, 'requestedBy': 'worker'},
        ]),
        'lastProgressStatus': _lastStatusString,
        'cancellationRequestedAt': FieldValue.serverTimestamp(),
        'status': 'cancellation_requested',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cancellation request submitted. Pending admin review.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      // Redirect to the dashboard and close this screen right away — the
      // worker doesn't wait around here for admin approval; onCancel (which
      // tears the gig down for real) only fires once that approval lands.
      //
      // Deferred a frame: WorkingUI isn't its own route — it's swapped out
      // inline by a ternary in gig_worker_screen.dart, so this callback's
      // setState structurally unmounts WorkingUI's whole subtree. Calling
      // it synchronously right after the reason dialog's Navigator.pop
      // (whose Future can resolve before the dialog's own exit
      // animation/overlay teardown finishes, especially once the Firestore
      // write above resolves near-instantly from local cache) tore down an
      // ancestor the still-closing dialog depended on mid-teardown,
      // tripping Flutter's `_dependents.isEmpty` assertion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCancellationRequested?.call();
      });
    } catch (e) {
      // Previously had no catch: a failed write (permission, network, a bad
      // multi-worker slot ref) surfaced nothing to the user — no error, no
      // redirect — leaving the screen looking silently stuck.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit cancellation request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  // ── Admin approved cancellation — notify and exit ─────────────────────────
  void _onAdminCancelled({bool byHost = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          byHost
              ? "The host's cancellation request was approved — this gig has been cancelled."
              : 'Your cancellation request has been approved.',
        ),
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
      slotWorkerId: _slotWorkerId,
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
      await RatingDialog.show(
        context: context,
        rateeId: hostId,
        rateeName: hostName,
        rateeRole: RateeRole.host,
        gigId: widget.gig.id,
        gigCollection: widget.gigCollection,
        gigTitle: widget.gig.title,
        slotWorkerId: _slotWorkerId,
      );
    }
    widget.onComplete();
  }

  // ── Fetch actual road route via OSRM ─────────────────────────────────────
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=polyline&steps=true',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as String;
      final decoded = PolylinePoints().decodePolyline(geometry);

      final durS = (route['duration'] as num?)?.toInt();

      final steps = <_RouteStep>[];
      final legs = route['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final rawSteps =
            (legs[0] as Map<String, dynamic>)['steps'] as List? ?? [];
        for (final s in rawSteps) {
          final step = s as Map<String, dynamic>;
          final dist = (step['distance'] as num?)?.toDouble() ?? 0;
          steps.add(
            _RouteStep(
              instruction: _buildStepInstruction(step),
              icon: _iconForStepData(step),
              distanceM: dist,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _routePoints = decoded
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
          _routeEtaSeconds = durS;
          _routeSteps = steps;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    _sheetController.dispose();
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
    final stepIndex = GigStep.values.indexOf(_step);
    final copy = workerInstructionFor(
      _step,
      amount: widget.gig.budget,
      currencyCode: widget.gig.currencyCode,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: activeGigScreenBg(isDark),
      body: Stack(
        children: [
          // ── Full-screen map, always underneath ──────────────────────
          Positioned.fill(
            child: _ActiveGigMapCard(
              gig: widget.gig,
              workerLocation: _workerLocation,
              // Once arrived there's no more route to travel — drop the
              // polyline so the map isn't showing stale directions to a
              // place the worker is already at.
              routePoints: _step == GigStep.navigating
                  ? _routePoints
                  : const [],
              // Straight-line distance, not the OSRM driving-route distance
              // — this is what the 40m arrival geofence (_checkGeofence)
              // actually compares against, so the number shown here always
              // matches what triggers "arrived" instead of a road-distance
              // figure that can read as "already within range" while the
              // geofence (correctly) hasn't fired yet.
              routeDistanceM:
                  _step == GigStep.navigating && _workerLocation != null
                  ? Geolocator.distanceBetween(
                      _workerLocation!.latitude,
                      _workerLocation!.longitude,
                      widget.gig.position.latitude,
                      widget.gig.position.longitude,
                    )
                  : null,
              // Keeps the fitted route/markers centered in the strip still
              // visible above the sheet, instead of behind it.
              bottomPadding:
                  MediaQuery.of(context).size.height *
                  (_sheetCollapsed ? _sheetMin : _sheetInitial),
            ),
          ),

          // ── Floating back button over the map ───────────────────────
          Positioned(
            top: topInset + 10,
            left: 12,
            child: MapRoundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),

          // ── Draggable bottom sheet — drag down to reveal the full map,
          // snaps between _sheetMin (collapsed) and _sheetInitial (open).
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _sheetInitial,
            minChildSize: _sheetMin,
            maxChildSize: _sheetInitial,
            snap: true,
            snapSizes: const [_sheetMin, _sheetInitial],
            builder: (ctx, scrollController) => Container(
              decoration: BoxDecoration(
                color: activeGigScreenBg(isDark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Drag handle — handled manually (jumpTo/animateTo)
                    // rather than relying solely on the sheet's built-in
                    // scroll-position-driven drag, since that coordination
                    // can get out-competed by the native map view sitting
                    // underneath wherever the sheet overlaps it.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if (!_sheetController.isAttached) return;
                        final screenHeight = MediaQuery.of(context).size.height;
                        final newSize =
                            (_sheetController.size -
                                    details.delta.dy / screenHeight)
                                .clamp(_sheetMin, _sheetInitial);
                        _sheetController.jumpTo(newSize);
                      },
                      onVerticalDragEnd: (details) {
                        if (!_sheetController.isAttached) return;
                        final current = _sheetController.size;
                        final mid = (_sheetMin + _sheetInitial) / 2;
                        final target = current < mid
                            ? _sheetMin
                            : _sheetInitial;
                        _sheetController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Location warning ─────────────────────
                            if (_locationWarning != null) ...[
                              Container(
                                width: double.infinity,
                                color: Colors.orange.shade700,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_off_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _locationWarning!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    if (_locationWarning!.contains('settings'))
                                      TextButton(
                                        onPressed: () =>
                                            Geolocator.openAppSettings(),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'Settings',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            ActiveGigProgressCard(
                              stepIndex: stepIndex,
                              title: copy.title,
                              body: copy.body,
                              elapsed: _step == GigStep.working
                                  ? _fmt(_elapsed)
                                  : null,
                              arrivedPromptVisible:
                                  !_cancelPending && _arrivedPromptVisible,
                              onConfirmArrival: _confirmArrival,
                              isCancelPending: _cancelPending,
                              cancelRequestedByHost: _cancelRequestedByHost,
                              showStartGig:
                                  !_cancelPending && _step == GigStep.arrived,
                              onStartGig: _startWork,
                              showGigComplete:
                                  !_cancelPending && _step == GigStep.working,
                              onGigComplete: _completeWork,
                              accent: kWorkerAccent,
                            ),
                            const SizedBox(height: 16),

                            // ── Reopen payment code entry (worker backed out of
                            // it earlier). _paymentConfirmShown only ever flips
                            // once — if the sheet gets dismissed via back press,
                            // nothing else re-triggers it, so this button calls
                            // _showWorkerPaymentConfirm directly instead of
                            // relying on that one-shot flag.
                            if (_step == GigStep.payment) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton.icon(
                                  onPressed: _showWorkerPaymentConfirm,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Enter Payment Code',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF22C55E),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            _GigHostCard(gig: widget.gig),

                            const SizedBox(height: 20),

                            // ── Cancel gig (only while still on the way /
                            // working) ──────────────────────────────────────
                            if (!_cancelPending &&
                                (_step == GigStep.navigating ||
                                    _step == GigStep.arrived ||
                                    _step == GigStep.working))
                              CancelGigSection(
                                onPressed: _showCancelReasonDialog,
                                label: 'Cancel Application',
                                caption:
                                    'Cancelling after being selected may affect your worker rating',
                              ),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Arrow-up button — only while the sheet is collapsed ─────
          if (_sheetCollapsed)
            Positioned(
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: MapRoundButton(
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: _toggleSheet,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full-bleed tracking map shown at the top of the active-gig screen —
//  edge-to-edge, no card border/radius, since it now fills its own section
//  instead of sitting embedded inside the scrollable content below.
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveGigMapCard extends StatefulWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final double? routeDistanceM;
  final double bottomPadding;

  const _ActiveGigMapCard({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    this.routeDistanceM,
    this.bottomPadding = 0,
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

  @override
  Widget build(BuildContext context) {
    final distText = widget.routeDistanceM != null
        ? ' · ${fmtDist(widget.routeDistanceM!)}'
        : '';
    // Below the floating back button / status pill the parent screen draws
    // over this map, so the legend never sits underneath them.
    final chipTop = MediaQuery.of(context).padding.top + 56;
    return Stack(
      children: [
        Positioned.fill(
          child: _NavMapCore(
            gig: widget.gig,
            workerLocation: widget.workerLocation,
            routePoints: widget.routePoints,
            onDestinationTap: _openNavigation,
            // Smaller than the default 60 so the fixed padding doesn't eat
            // too much of the frame and force excess zoom-out.
            fitPadding: 20,
            bottomPadding: widget.bottomPadding,
          ),
        ),
        Positioned(
          left: 8,
          top: chipTop,
          child: MapInfoChip(
            primaryLabel: 'You',
            primaryDotColor: kWorkerAccent.solid,
            secondaryLabel: 'Gig  - - Route$distText',
            secondaryDotColor: Colors.red,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Navigation map core — renders the Google/OSM map, always full-bleed within
//  whatever bounds its parent gives it.
// ─────────────────────────────────────────────────────────────────────────────
class _NavMapCore extends StatefulWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final VoidCallback? onDestinationTap;
  final double fitPadding;
  // Extra bottom inset, in logical pixels, matching how much of the map
  // the draggable bottom sheet currently covers — keeps the fitted
  // route/markers centered in the visible area instead of behind it.
  final double bottomPadding;

  const _NavMapCore({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    this.onDestinationTap,
    this.fitPadding = 60,
    this.bottomPadding = 0,
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
        widget.routePoints.length != oldWidget.routePoints.length ||
        widget.bottomPadding != oldWidget.bottomPadding) {
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
          padding: EdgeInsets.fromLTRB(
            widget.fitPadding,
            widget.fitPadding,
            widget.fitPadding,
            widget.fitPadding + widget.bottomPadding,
          ),
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
          title: widget.gig.title.isNotEmpty
              ? widget.gig.title
              : 'Gig Location',
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
        ? ll.LatLng(
            widget.workerLocation!.latitude,
            widget.workerLocation!.longitude,
          )
        : null;
    final osmMarkers = <fm.Marker>[];
    if (workerPos != null) {
      osmMarkers.add(
        fm.Marker(
          point: workerPos,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.lightBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      );
    }
    osmMarkers.add(
      fm.Marker(
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
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(
              Icons.work_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    );
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
          flags:
              fm.InteractiveFlag.pinchZoom |
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

  @override
  Widget build(BuildContext context) {
    final gigPos = LatLng(
      widget.gig.position.latitude,
      widget.gig.position.longitude,
    );
    final initialTarget = widget.workerLocation ?? gigPos;

    final mapWidget = _useGoogleMaps
        ? GoogleMap(
            style: Theme.of(context).brightness == Brightness.dark
                ? kDarkMapStyle
                : null,
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
            padding: EdgeInsets.only(bottom: widget.bottomPadding),
            markers: _buildGoogleMarkers(),
            polylines: _buildPolylines(),
            // No EagerGestureRecognizer override here — this map is now the
            // full-screen background behind a DraggableScrollableSheet, and
            // an eager recognizer on the map would win every gesture arena
            // contest against the sheet's own drag handling, making the
            // sheet undraggable wherever it overlaps the map.
          )
        : _buildOsmMap();

    return mapWidget;
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
        color: activeGigCardBg(isDark),
        borderRadius: BorderRadius.circular(kActiveGigCardRadius),
        border: Border.all(color: activeGigCardBorder(isDark)),
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
                    color: activeGigTextPrimary(isDark),
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
                      text: CurrencyFormatter.format(
                        gig.payType == 'hourly' && gig.hourlyRate != null
                            ? gig.hourlyRate!
                            : gig.budget,
                        gig.currencyCode,
                      ),
                      style: TextStyle(
                        color: kWorkerAccent.solid,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: gig.payType == 'hourly'
                          ? ' / hr'
                          : gig.isMultiWorker
                          ? ' / you'
                          : ' / gig',
                      style: TextStyle(
                        color: activeGigTextMuted(isDark),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (gig.isMultiWorker) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.groups_rounded,
                  color: activeGigTextMuted(isDark),
                  size: 12,
                ),
                const SizedBox(width: 5),
                Text(
                  'You\'re one of ${gig.workerSlots} workers on this gig, paid independently',
                  style: TextStyle(
                    color: activeGigTextMuted(isDark),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ],
          if (gig.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: activeGigTextMuted(isDark),
                  size: 14,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    dedupedAddress(gig.address),
                    style: TextStyle(
                      color: activeGigTextMuted(isDark),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(
            height: 0,
            thickness: 1,
            color: activeGigDividerColor(isDark),
          ),
          const SizedBox(height: 14),
          if (gig.hostId.isNotEmpty)
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kWorkerAccent.solid.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: TextStyle(
                      color: kWorkerAccent.solid,
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
                          color: activeGigTextPrimary(isDark),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Your host',
                        style: TextStyle(
                          color: activeGigTextMuted(isDark),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                PartyActionCircle(
                  bg: kWorkerAccent.solid.withValues(alpha: 0.12),
                  child: CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.voice,
                    iconColor: kWorkerAccent.solid,
                    gigId: gig.id,
                    viewerIsWorker: true,
                  ),
                ),
                const SizedBox(width: 8),
                PartyActionCircle(
                  bg: kWorkerAccent.solid.withValues(alpha: 0.12),
                  child: CallUserAction(
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    callType: CallType.video,
                    iconColor: kWorkerAccent.solid,
                    gigId: gig.id,
                    viewerIsWorker: true,
                  ),
                ),
                const SizedBox(width: 8),
                PartyActionCircle(
                  bg: kWorkerAccent.solid,
                  child: GigChatAction(
                    gigId: gig.id,
                    targetUserId: gig.hostId,
                    targetUserName: gig.hostName,
                    iconColor: Colors.white,
                    viewerIsWorker: true,
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
            child: const Icon(
              Icons.cancel_outlined,
              color: Colors.redAccent,
              size: 28,
            ),
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
              hintStyle: TextStyle(
                color: kSub.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go Back', style: TextStyle(color: kSub)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasText
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.redAccent.withValues(
                      alpha: 0.35,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Submit Request',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
