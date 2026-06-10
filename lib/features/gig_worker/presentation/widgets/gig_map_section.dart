import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────────────────────
class GigMarkerData {
  final String id;
  final String title;
  final String gigType; // 'quick' | 'open' | 'offered'
  final double budget;
  final String status;
  final String hostName;
  final String address;
  final LatLng position;
  final String? assignedWorkerId;
  final String experienceLevel;
  final List<String> requiredSkills;
  final String hostId;
  final bool hasApplied;

  const GigMarkerData({
    required this.id,
    required this.title,
    required this.gigType,
    required this.budget,
    required this.status,
    required this.hostName,
    required this.address,
    required this.position,
    this.assignedWorkerId,
    this.experienceLevel = '',
    this.requiredSkills = const [],
    required this.hostId,
    this.hasApplied = false,
  });
}

class _GigCluster {
  final LatLng center;
  final int count;
  final GigMarkerData? singleGig;
  final List<GigMarkerData> gigs;

  const _GigCluster({
    required this.center,
    required this.count,
    required this.gigs,
    this.singleGig,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Map Section
// ─────────────────────────────────────────────────────────────────────────────
class GigMapSection extends StatefulWidget {
  final String uid;
  final String workerName;
  final bool seekingQuickGigs;
  final ValueChanged<GigMarkerData>? onQuickGigStarted;
  final ValueChanged<GigMarkerData>? onOpenGigApplied;
  final String isVerified;
  final List<String> workerSkills;

  const GigMapSection({
    super.key,
    required this.uid,
    required this.workerName,
    required this.seekingQuickGigs,
    this.onQuickGigStarted,
    this.onOpenGigApplied,
    required this.isVerified,
    this.workerSkills = const [],
  });

  @override
  State<GigMapSection> createState() => _GigMapSectionState();
}

class _GigMapSectionState extends State<GigMapSection> {
  final _mapController = MapController();
  double _zoom = 12.0;
  LatLng? _myLocation;

  List<GigMarkerData> _quickGigs = [];
  List<GigMarkerData> _openGigs = [];
  List<GigMarkerData> _offeredGigs = [];

  StreamSubscription? _quickSub;
  late StreamSubscription _openSub, _offeredSub;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _startOpenSub(db);
    _startOfferedSub(db);
    if (widget.seekingQuickGigs) _startQuickSub(db);
    _fetchAndCenterMap();
  }

  Future<void> _fetchAndCenterMap() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return; }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, 14.0);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(GigMapSection old) {
    super.didUpdateWidget(old);
    if (old.seekingQuickGigs != widget.seekingQuickGigs) {
      if (widget.seekingQuickGigs) {
        _startQuickSub(FirebaseFirestore.instance);
      } else {
        _quickSub?.cancel();
        _quickSub = null;
        setState(() => _quickGigs = []);
      }
    }
  }

  void _startQuickSub(FirebaseFirestore db) {
    _quickSub = db
        .collection('quick_gigs')
        .where('status', whereIn: ['scanning', 'in_progress'])
        .snapshots()
        .listen((s) {
      final all = s.docs.map((d) {
        final data = d.data();
        final status = data['status'] as String? ?? '';
        if (status == 'in_progress' &&
            data['assignedWorkerId'] != widget.uid) {
          return null;
        }
        return _toMarker(d.id, data, 'quick');
      }).whereType<GigMarkerData>().toList();
      setState(() => _quickGigs = all);
    }, onError: (e) => debugPrint('[GigMap] quick stream error: $e'));
  }

  void _startOpenSub(FirebaseFirestore db) {
    _openSub = db
        .collection('open_gigs')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((s) {
      setState(() {
        _openGigs = s.docs
            .where((d) => (d.data()['hostId'] as String?) != widget.uid)
            .map((d) => _toMarker(d.id, d.data(), 'open', workerUid: widget.uid))
            .whereType<GigMarkerData>()
            .toList();
      });
    }, onError: (e) => debugPrint('[GigMap] open stream error: $e'));
  }

  void _startOfferedSub(FirebaseFirestore db) {
    _offeredSub = db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen((s) {
      setState(() {
        _offeredGigs = s.docs
            .map((d) => _toMarker(d.id, d.data(), 'offered'))
            .whereType<GigMarkerData>()
            .toList();
      });
    }, onError: (e) => debugPrint('[GigMap] offered stream error: $e'));
  }

  Future<void> _applyToOpenGig(GigMarkerData gig) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('open_gigs')
          .doc(gig.id)
          .get();

      if (!snap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This gig no longer exists.'),
            backgroundColor: Colors.redAccent,
          ));
        }
        return;
      }
      final currentStatus = snap.data()?['status'] as String? ?? '';
      if (currentStatus != 'open') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gig is no longer available (status: $currentStatus).'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      // Prevent double-apply
      final existing = List<dynamic>.from(snap.data()?['applicants'] ?? []);
      final alreadyApplied = existing.any(
          (a) => (a as Map<String, dynamic>)['workerId'] == widget.uid);
      if (alreadyApplied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You have already applied to this gig.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('open_gigs')
          .doc(gig.id)
          .update({
        'applicants': FieldValue.arrayUnion([
          {'workerId': widget.uid, 'workerName': widget.workerName},
        ]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Application submitted! Waiting for host selection.'),
          backgroundColor: Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('[GigMap] apply to open gig error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to apply: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _quickSub?.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  GigMarkerData? _toMarker(
      String id, Map<String, dynamic> data, String type, {String workerUid = ''}) {
    final geo = data['location'] as GeoPoint?;
    if (geo == null) return null;
    final applicants = List<dynamic>.from(data['applicants'] ?? []);
    final hasApplied = type == 'open' &&
        workerUid.isNotEmpty &&
        applicants.any((a) => (a as Map<String, dynamic>)['workerId'] == workerUid);
    return GigMarkerData(
      id: id,
      title: data['title'] as String? ?? 'Untitled Gig',
      gigType: type,
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      address: data['address'] as String? ?? '',
      position: LatLng(geo.latitude, geo.longitude),
      assignedWorkerId: data['assignedWorkerId'] as String?,
      experienceLevel: data['experienceLevel'] as String? ?? '',
      requiredSkills: List<String>.from(data['requiredSkills'] ?? []),
      hostId: data['hostId'] as String? ?? '',
      hasApplied: hasApplied,
    );
  }

  List<GigMarkerData> get _allGigs =>
      [..._quickGigs, ..._openGigs, ..._offeredGigs];

  static double _gridSize(double zoom) {
    if (zoom < 10) return 0.15;
    if (zoom < 11) return 0.08;
    if (zoom < 12) return 0.04;
    if (zoom < 13) return 0.02;
    if (zoom < 14) return 0.008;
    if (zoom < 16) return 0.0005;
    return 0.0002; // ≈ 22 m — always cluster gigs this close together
  }

  List<_GigCluster> _buildClusters() {
    final all = _allGigs;
    final gridSize = _gridSize(_zoom);

    final Map<String, List<GigMarkerData>> grid = {};
    for (final g in all) {
      final latKey = (g.position.latitude / gridSize).floor();
      final lngKey = (g.position.longitude / gridSize).floor();
      grid.putIfAbsent('$latKey:$lngKey', () => []).add(g);
    }

    return grid.values.map((group) {
      final avgLat =
          group.fold(0.0, (s, g) => s + g.position.latitude) / group.length;
      final avgLng =
          group.fold(0.0, (s, g) => s + g.position.longitude) / group.length;
      return _GigCluster(
        center: LatLng(avgLat, avgLng),
        count: group.length,
        gigs: group,
        singleGig: group.length == 1 ? group.first : null,
      );
    }).toList();
  }

  List<Marker> _buildMarkers() {
  return _buildClusters().map((cluster) {
    if (cluster.count == 1 && cluster.singleGig != null) {
      final singleGig = cluster.singleGig!;
      return Marker(
        point: cluster.center,
        width: 40,
        height: 48,
        child: _GigPin(
          gig: singleGig,
          isVerified: widget.isVerified,
          workerSkills: widget.workerSkills,
          onStart: singleGig.gigType == 'quick' &&
                  singleGig.assignedWorkerId == widget.uid
              ? () => widget.onQuickGigStarted?.call(singleGig)
              : null,
          onApply: singleGig.gigType == 'open'
              ? () => _applyToOpenGig(singleGig)
              : null,
        ),
      );
    }

    return Marker(
      point: cluster.center,
      width: 60,
      height: 60,
      child: _GigClusterBadge(
        count: cluster.count,
        gigs: cluster.gigs,
        isVerified: widget.isVerified,
        workerSkills: widget.workerSkills,
        onQuickGigStarted: widget.onQuickGigStarted,
        onOpenGigApplied: _applyToOpenGig,
      ),
    );
  }).toList();
}

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;
    final total = _allGigs.length;
    final offeredCount = _offeredGigs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Gigs Near You',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ),
            if (offeredCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$offeredCount Offered',
                  style: const TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAmber.withValues(alpha: 0.4)),
              ),
              child: Text(
                '$total ${total == 1 ? 'Gig' : 'Gigs'}',
                style: const TextStyle(
                    color: kAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (widget.seekingQuickGigs) ...[
              _LegendDot(color: kAmber, label: 'Quick'),
              const SizedBox(width: 14),
            ],
            _LegendDot(color: kBlue, label: 'Open'),
            const SizedBox(width: 14),
            _LegendDot(
                color: const Color(0xFF8B5CF6), label: 'Offered to me'),
          ],
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(14.5995, 120.9842),
                    initialZoom: 12.0,
                    minZoom: 9.0,
                    maxZoom: 18.0,
                    onMapEvent: (event) {
                      final newZoom = _mapController.camera.zoom;
                      if ((newZoom - _zoom).abs() >= 0.3) {
                        setState(() => _zoom = newZoom);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.giggre.app',
                    ),
                    MarkerLayer(markers: _buildMarkers()),
                    if (_myLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _myLocation!,
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: kBlue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: kBlue.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // Recenter button
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: _fetchAndCenterMap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.my_location_rounded,
                    size: 18,
                    color: _myLocation != null ? kBlue : kSub,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Zoom in to see individual gigs · Tap a pin for details',
            style: TextStyle(
                color: kSub.withValues(alpha: 0.7), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Legend dot
// ─────────────────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: kSub, fontSize: 11)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Pin (single marker)
// ─────────────────────────────────────────────────────────────────────────────
class _GigPin extends StatelessWidget {
  final GigMarkerData gig;
  final String isVerified;
  final List<String> workerSkills;
  final VoidCallback? onStart;
  final VoidCallback? onApply;
  const _GigPin({
    required this.gig,
    required this.isVerified,
    this.workerSkills = const [],
    this.onStart,
    this.onApply,
  });

  Color get _pinColor {
    switch (gig.gigType) {
      case 'open':    return kBlue;
      case 'offered': return const Color(0xFF8B5CF6);
      default:        return kAmber;
    }
  }

  IconData get _pinIcon {
    switch (gig.gigType) {
      case 'open':    return Icons.workspace_premium_outlined;
      case 'offered': return Icons.send_rounded;
      default:        return Icons.flash_on_rounded;
    }
  }

  List<String> _missingSkills() {
    if (gig.gigType != 'open' || gig.requiredSkills.isEmpty) return [];
    return gig.requiredSkills
        .where((s) => !workerSkills.any(
            (ws) => ws.toLowerCase().trim() == s.toLowerCase().trim()))
        .toList();
  }

  void _showGigSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final color = _pinColor;
        final typeLabel = gig.gigType == 'open'
            ? 'Open Gig'
            : gig.gigType == 'offered'
                ? 'Offered to You'
                : 'Quick Gig';
        final isAppliedPending = gig.gigType == 'open' && gig.hasApplied;
        final btnLabel = isAppliedPending
            ? 'Application Pending'
            : gig.gigType == 'open'
                ? 'Apply Now'
                : gig.gigType == 'offered'
                    ? 'Accept Offer'
                    : 'Start Gig';
        final missing = _missingSkills();
        final canApply = missing.isEmpty;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_pinIcon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(gig.title,
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(typeLabel,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _GigSheetRow(
                icon: Icons.person_outline_rounded,
                label: 'Host',
                value: gig.hostName.isNotEmpty ? gig.hostName : '—',
              ),
              _GigSheetRow(
                icon: Icons.attach_money_rounded,
                label: 'Budget',
                value: '₱${gig.budget.toStringAsFixed(0)}',
                valueColor: kAmber,
              ),
              if (gig.address.isNotEmpty)
                _GigSheetRow(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  value: gig.address,
                ),
              if (gig.experienceLevel.isNotEmpty)
                _GigSheetRow(
                  icon: Icons.bar_chart_rounded,
                  label: 'Experience',
                  value: gig.experienceLevel,
                ),
              if (gig.requiredSkills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.construction_rounded,
                        color: kSub, size: 16),
                    const SizedBox(width: 8),
                    const Text('Skills: ',
                        style: TextStyle(color: kSub, fontSize: 13)),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: gig.requiredSkills.map((s) {
                          final has = workerSkills.any((ws) =>
                              ws.toLowerCase().trim() ==
                              s.toLowerCase().trim());
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: has
                                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                  : Colors.red.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: has
                                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                      : Colors.red.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  has ? Icons.check_circle_outline : Icons.cancel_outlined,
                                  size: 11,
                                  color: has ? const Color(0xFF10B981) : Colors.red,
                                ),
                                const SizedBox(width: 3),
                                Text(s,
                                    style: TextStyle(
                                        color: has
                                            ? const Color(0xFF10B981)
                                            : Colors.red,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.red, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You lack ${missing.length == 1 ? 'a required skill' : '${missing.length} required skills'}: ${missing.join(', ')}',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: (canApply && !isAppliedPending)
                      ? () {
                          if (isVerified != 'verified') {
                            _showModal(context);
                            return;
                          }
                          Navigator.pop(ctx);
                          if (gig.gigType == 'quick') {
                            onStart?.call();
                          } else if (gig.gigType == 'open') {
                            onApply?.call();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canApply ? color : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isAppliedPending
                        ? kAmber.withValues(alpha: 0.75)
                        : Colors.grey.shade400,
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isAppliedPending) ...[
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        isAppliedPending
                            ? 'Application Pending'
                            : canApply ? btnLabel : 'Skills Required',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _pinColor;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: GestureDetector(
        onTap: () => _showGigSheet(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(_pinIcon, color: Colors.white, size: 18),
            ),
            CustomPaint(
              painter: _TrianglePainter(color: color),
              size: const Size(10, 6),
            ),
          ],
        ),
      ),
    );
  }
}

class _GigSheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _GigSheetRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: kSub, size: 16),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: kSub, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ??
                        Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cluster badge
// ─────────────────────────────────────────────────────────────────────────────
class _GigClusterBadge extends StatefulWidget {
  final int count;
  final List<GigMarkerData> gigs;
  final String isVerified;
  final List<String> workerSkills;
  final ValueChanged<GigMarkerData>? onQuickGigStarted;
  final ValueChanged<GigMarkerData>? onOpenGigApplied;
  const _GigClusterBadge({
    required this.count,
    required this.gigs,
    required this.isVerified,
    this.workerSkills = const [],
    this.onQuickGigStarted,
    this.onOpenGigApplied,
  });

  @override
  State<_GigClusterBadge> createState() => _GigClusterBadgeState();
}

class _GigClusterBadgeState extends State<_GigClusterBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseScale = Tween<double>(begin: 1.0, end: 1.9)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(begin: 0.55, end: 0.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _showGigList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.work_outline_rounded,
                          color: kAmber, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.count} Gigs in this area',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const Text('Tap a gig to see details',
                            style: TextStyle(color: kSub, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                  color: isDark
                      ? kBorder.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.15)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: widget.gigs.length,
                  separatorBuilder: (_, i) => Divider(
                    height: 1,
                    color: isDark
                        ? kBorder.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (_, i) {
                    final g = widget.gigs[i];
                    final typeColor = g.gigType == 'open'
                        ? kBlue
                        : g.gigType == 'offered'
                            ? const Color(0xFF8B5CF6)
                            : kAmber;
                    final typeIcon = g.gigType == 'open'
                        ? Icons.workspace_premium_outlined
                        : g.gigType == 'offered'
                            ? Icons.send_rounded
                            : Icons.flash_on_rounded;
                    final typeLabel = g.gigType == 'open'
                        ? 'Open'
                        : g.gigType == 'offered'
                            ? 'Offered'
                            : 'Quick';
                    final btnLabel = g.gigType == 'open'
                        ? 'Apply'
                        : g.gigType == 'offered'
                            ? 'Accept'
                            : 'Start';
                    final missing = g.gigType == 'open' &&
                            g.requiredSkills.isNotEmpty
                        ? g.requiredSkills
                            .where((s) => !widget.workerSkills.any((ws) =>
                                ws.toLowerCase().trim() ==
                                s.toLowerCase().trim()))
                            .toList()
                        : <String>[];
                    final canApply = missing.isEmpty;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 20),
                      ),
                      title: Text(g.title,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(typeLabel,
                                    style: TextStyle(
                                        color: typeColor, fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₱${g.budget.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: kAmber,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (missing.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Missing: ${missing.join(', ')}',
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: canApply
                            ? () {
                                if (widget.isVerified != 'verified') {
                                  Navigator.pop(ctx);
                                  _showModal(context);
                                  return;
                                }
                                Navigator.pop(ctx);
                                if (g.gigType == 'quick') {
                                  widget.onQuickGigStarted?.call(g);
                                } else if (g.gigType == 'open') {
                                  widget.onOpenGigApplied?.call(g);
                                }
                              }
                            : null,
                        style: TextButton.styleFrom(
                          backgroundColor: canApply
                              ? typeColor.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          foregroundColor:
                              canApply ? typeColor : Colors.grey,
                          disabledForegroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          canApply ? btnLabel : 'Locked',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: kAmber,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: kAmber.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${widget.count}',
            style: const TextStyle(
                color: Colors.black,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                height: 1),
          ),
          const Text(
            'gigs',
            style: TextStyle(
                color: Colors.black87, fontSize: 8, letterSpacing: 0.3),
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (_, entryScale, child) =>
          Transform.scale(scale: entryScale, child: child),
      child: GestureDetector(
        onTap: () => _showGigList(context),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing ring
                Transform.scale(
                  scale: _pulseScale.value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kAmber.withValues(alpha: _pulseOpacity.value),
                        width: 2.5,
                      ),
                      color: kAmber
                          .withValues(alpha: _pulseOpacity.value * 0.25),
                    ),
                  ),
                ),
                // Main badge
                child!,
              ],
            ),
          ),
          child: badge,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Triangle pointer painter
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

void _showModal(
  BuildContext context, 
) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ( Colors.red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Account not Verified',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account needs to be verified before you can continue. Please request verification from the admin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:  Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}