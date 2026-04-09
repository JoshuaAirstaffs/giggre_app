import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import '../../../../core/theme/app_colors.dart';
import 'gig_map_section.dart';

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
//  Working UI — full-screen view shown when a quick gig is active
// ─────────────────────────────────────────────────────────────────────────────
class WorkingUI extends StatefulWidget {
  final GigMarkerData gig;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const WorkingUI({
    super.key,
    required this.gig,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<WorkingUI> createState() => _WorkingUIState();
}

class _WorkingUIState extends State<WorkingUI> {
  _GigStep _step = _GigStep.navigating;

  // Stopwatch (working step)
  late final Stopwatch _stopwatch;
  late final Timer _timer;
  Duration _elapsed = Duration.zero;

  // Worker location tracking
  LatLng? _workerLocation;
  StreamSubscription<Position>? _locationSub;
  bool _geofenceTriggered = false;
  static const _arrivedThresholdMeters = 40.0;

  // Actual road route
  List<LatLng> _routePoints = [];
  LatLng? _lastRouteFetch;

  // Firestore live listener
  StreamSubscription? _gigSub;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stopwatch.isRunning) {
        setState(() => _elapsed = _stopwatch.elapsed);
      }
    });
    _listenGig();
    _startLocation();
  }

  // ── Firestore listener ────────────────────────────────────────────────────
  void _listenGig() {
    _gigSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(widget.gig.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final status = snap.data()?['status'] as String? ?? 'navigating';
      final newStep = _stepFromStatus(status);
      if (newStep != _step) {
        setState(() => _step = newStep);
        if (newStep == _GigStep.working && !_stopwatch.isRunning) {
          _stopwatch.start();
        }
        if (newStep == _GigStep.completed) {
          widget.onComplete();
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
          final shouldFetch = _lastRouteFetch == null ||
              Geolocator.distanceBetween(
                _lastRouteFetch!.latitude, _lastRouteFetch!.longitude,
                loc.latitude, loc.longitude,
              ) > 30;
          if (shouldFetch) {
            _lastRouteFetch = loc;
            _fetchRoute(loc, widget.gig.position);
          }
        }
      });
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
      _updateStatus('arrived');
    }
  }

  Future<void> _updateStatus(String status) async {
    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(widget.gig.id)
        .update({'status': status});
  }

  // ── Fetch actual road route via OSRM ─────────────────────────────────────
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=polyline',
      );
      final response = await http.get(uri);
      if (!mounted || response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final geometry = routes[0]['geometry'] as String;
      final decoded = PolylinePoints().decodePolyline(geometry);
      if (mounted) {
        setState(() {
          _routePoints = decoded
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
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
                    if (_step == _GigStep.navigating)
                      _NavigatingSection(
                        gig: widget.gig,
                        workerLocation: _workerLocation,
                        routePoints: _routePoints,
                        divider: divider,
                      ),
                    if (_step == _GigStep.arrived)
                      _StatusBanner(
                        icon: Icons.location_on_rounded,
                        color: green,
                        title: "You've Arrived!",
                        subtitle: 'Tap Start Gig when you\'re ready to begin.',
                      ),
                    if (_step == _GigStep.working)
                      _TimerBanner(elapsed: _fmt(_elapsed)),
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
                        onPressed: () => _updateStatus('working'),
                      ),
                    if (_step == _GigStep.working)
                      _PrimaryButton(
                        label: 'Gig Complete',
                        icon: Icons.check_circle_outline_rounded,
                        color: green,
                        onPressed: () async {
                          _stopwatch.stop();
                          await _updateStatus('task_complete');
                        },
                      ),

                    // ── Cancel gig (only while still on the way / working) ─
                    if (_step == _GigStep.navigating ||
                        _step == _GigStep.arrived ||
                        _step == _GigStep.working)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: widget.onCancel,
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
class _NavigatingSection extends StatelessWidget {
  final GigMarkerData gig;
  final LatLng? workerLocation;
  final List<LatLng> routePoints;
  final Color divider;
  const _NavigatingSection({
    required this.gig,
    required this.workerLocation,
    required this.routePoints,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {

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
              border: Border.all(color: divider),
            ),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: workerLocation ?? gig.position,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.giggre.app',
                ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: kBlue,
                        strokeWidth: 4.0,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (workerLocation != null)
                      Marker(
                        point: workerLocation!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: kBlue,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: kBlue.withValues(alpha: 0.45),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    Marker(
                      point: gig.position,
                      width: 40,
                      height: 48,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: kAmber,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: kAmber.withValues(alpha: 0.45),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.flash_on_rounded,
                                color: Colors.white, size: 18),
                          ),
                          CustomPaint(
                            painter: _TrianglePainter(color: kAmber),
                            size: const Size(10, 6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Auto-detected at 40 m · Blue dot = you · Amber pin = gig · Blue line = route',
            style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 10),
          ),
        ),
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
  const _TimerBanner({required this.elapsed});

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
                const Text('Quick Gig — Active',
                    style: TextStyle(
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

  (String, Color) get _statusInfo {
    const green = Color(0xFF22C55E);
    switch (step) {
      case _GigStep.navigating:
        return ('Navigating', kBlue);
      case _GigStep.arrived:
        return ('Arrived at Location', green);
      case _GigStep.working:
        return ('In Progress', green);
      case _GigStep.taskComplete:
        return ('Task Complete', kAmber);
      case _GigStep.payment:
        return ('Payment Pending', kBlue);
      case _GigStep.completed:
        return ('Completed', green);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusInfo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.flash_on_rounded,
                    color: kAmber, size: 22),
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
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Quick Gig',
                          style: TextStyle(
                              color: kAmber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: divider),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Host',
            value: gig.hostName.isNotEmpty ? gig.hostName : '—',
          ),
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
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: kSub, size: 17),
            const SizedBox(width: 10),
            Text('$label  ',
                style: const TextStyle(color: kSub, fontSize: 13)),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor ??
                      Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
//  Triangle painter for map pin pointer
// ─────────────────────────────────────────────────────────────────────────────
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
