import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/gms_availability.dart';
import '../../../../core/utils/country_check.dart';
import '../../../../core/utils/currency_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────────────────────
class GigMarkerData {
  final String id;
  final String title;
  final String gigType; // 'quick' | 'open' | 'offered'
  final double budget;
  final String currencyCode;
  final String status;
  final String hostName;
  final String address;
  final LatLng position;
  final String? assignedWorkerId;
  final String experienceLevel;
  final List<String> requiredSkills;
  final String hostId;
  final bool hasApplied;
  final DateTime? scheduledDate;

  const GigMarkerData({
    required this.id,
    required this.title,
    required this.gigType,
    required this.budget,
    this.currencyCode = 'PHP',
    required this.status,
    required this.hostName,
    required this.address,
    required this.position,
    this.assignedWorkerId,
    this.experienceLevel = '',
    this.requiredSkills = const [],
    required this.hostId,
    this.hasApplied = false,
    this.scheduledDate,
  });
}

enum _SkillFilter { all, mySkills, specific }

// Rounds a coordinate to a ~1km grid so nearby gigs share one reverse-geocode
// lookup instead of firing one per gig.
String _countryCacheKey(double lat, double lng) =>
    '${(lat * 100).round()},${(lng * 100).round()}';

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
  final bool fullScreen;

  const GigMapSection({
    super.key,
    required this.uid,
    required this.workerName,
    required this.seekingQuickGigs,
    this.onQuickGigStarted,
    this.onOpenGigApplied,
    required this.isVerified,
    this.workerSkills = const [],
    this.fullScreen = false,
  });

  @override
  State<GigMapSection> createState() => _GigMapSectionState();
}

class _GigMapSectionState extends State<GigMapSection> {
  GoogleMapController? _googleMapController;
  double _zoom = 12.0;
  LatLng? _myLocation;
  bool _mapInteractive = false;
  bool _useGoogleMaps = true;
  final _osmController = fm.MapController();
  bool _osmMapReady = false;

  // Store context for use in marker callbacks
  BuildContext? _context;

  // Marker-triggered sheets (gig / cluster) are tagged with this route name so
  // we can close any that are already open before showing a new one — instead
  // of relying on a plain flag, which races when an "outside tap" dismissal
  // and a new marker tap land at the same time (e.g. two simultaneous touches)
  // and can end up popping the wrong route. popUntil only ever removes routes
  // carrying this name, so it can't reach past our own sheets into the
  // underlying screen, and it's a safe no-op if none are open.
  static const _markerSheetRouteName = 'gig_marker_sheet';

  void _openMarkerSheet(
    BuildContext context,
    WidgetBuilder builder, {
    bool isScrollControlled = false,
  }) {
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name != _markerSheetRouteName);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      routeSettings: const RouteSettings(name: _markerSheetRouteName),
      builder: builder,
    );
  }

  List<GigMarkerData> _quickGigs = [];
  List<GigMarkerData> _openGigs = [];
  List<GigMarkerData> _offeredGigs = [];

  StreamSubscription? _quickSub;
  late StreamSubscription _openSub, _offeredSub;

  // ── Country matching (only show gigs in the worker's own country) ─────────
  String? _myCountryCode;
  final Map<String, String> _countryCodeCache = {};
  final Set<String> _resolvingCountryKeys = {};
  final List<GigMarkerData> _pendingCountryQueue = [];
  bool _isResolvingCountries = false;

  // ── Filters ──────────────────────────────────────────────────────────────
  _SkillFilter _skillFilter = _SkillFilter.all;
  String? _specificSkill;
  double? _radiusKm; // null = no radius limit
  List<String> _allSkillNames = [];

  // ── Fetch full skill list from Firestore /skills (used by Specific Skill filter)
  Future<void> _fetchAllSkills() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('skills').get();
      final names =
          snap.docs
              .where((d) => d.id != '_counter')
              .map((d) => (d.data()['name'] as String?) ?? d.id)
              .where((s) => s.isNotEmpty)
              .toList()
            ..sort();
      if (mounted) setState(() => _allSkillNames = names);
    } catch (_) {}
  }

  // ── Custom marker icon cache ─────────────────────────────────────────────
  final Map<String, BitmapDescriptor> _icons = {};

  Future<BitmapDescriptor> _makeMarkerIcon(Color color, {String? label}) async {
    const px = 20.0;
    const r = 8.0;
    const cx = px / 2;
    const cy = px / 2;

    final rec = ui.PictureRecorder();
    final can = Canvas(rec);

    // Fill
    can.drawCircle(const Offset(cx, cy), r, Paint()..color = color);
    // White border
    can.drawCircle(
      const Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    if (label != null) {
      final fs = label.length <= 2 ? 7.0 : 5.5;
      final pb =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.center,
                fontSize: fs,
                fontWeight: FontWeight.bold,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: fs,
              ),
            )
            ..addText(label);
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: px));
      can.drawParagraph(para, Offset(0, cy - para.height / 2));
    }

    final img = await rec.endRecording().toImage(px.toInt(), px.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  Future<void> _loadBaseIcons() async {
    try {
      final results = await Future.wait([
        _makeMarkerIcon(kAmber),
        _makeMarkerIcon(kBlue),
        _makeMarkerIcon(const Color(0xFF8B5CF6)),
        _makeMarkerIcon(const Color(0xFF22D3EE)),
        _makeMarkerIcon(const Color(0xFFF97316), label: '…'),
      ]);
      _icons['quick'] = results[0];
      _icons['open'] = results[1];
      _icons['offered'] = results[2];
      _icons['location'] = results[3];
      _icons['cluster_default'] = results[4];
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[GigMap] icon load error: $e');
    }
  }

  BitmapDescriptor _gigIcon(String type) =>
      _icons[type] ?? BitmapDescriptor.defaultMarkerWithHue(_hueForType(type));

  BitmapDescriptor _resolveClusterIcon(int count) {
    final key = 'cluster_$count';
    if (_icons.containsKey(key)) return _icons[key]!;
    final label = count > 99 ? '99+' : '$count';
    _makeMarkerIcon(const Color(0xFFF97316), label: label).then((icon) {
      _icons[key] = icon;
      if (mounted) setState(() {});
    });
    return _icons['cluster_default'] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  @override
  void initState() {
    super.initState();
    _mapInteractive = widget.fullScreen;
    _loadBaseIcons();
    _fetchAllSkills();
    final db = FirebaseFirestore.instance;
    _startOpenSub(db);
    _startOfferedSub(db);
    _startQuickSub(db);
    _initMap();
  }

  Future<void> _initMap() async {
    final hasGms = await GmsAvailability.isAvailable;
    if (mounted) setState(() => _useGoogleMaps = hasGms);
    _fetchAndCenterMap();
  }

  Future<void> _fetchAndCenterMap() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location is off. Enable GPS to center the map on you.',
              ),
              action: SnackBarAction(
                label: 'Enable',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                perm == LocationPermission.deniedForever
                    ? 'Location permanently denied. Enable it in app settings.'
                    : 'Location permission denied.',
              ),
              action: perm == LocationPermission.deniedForever
                  ? SnackBarAction(
                      label: 'Settings',
                      onPressed: () => Geolocator.openAppSettings(),
                    )
                  : null,
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = loc);
      _resolveMyCountry(loc);
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(loc, 14.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(ll.LatLng(loc.latitude, loc.longitude), 14.0);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location.')),
        );
      }
    }
  }

  // Reverse-geocodes the worker's own position to find which country they're
  // in, so the map can hide gigs posted from elsewhere. Retries a few times
  // with backoff since this single lookup gates the entire filter — if it
  // never resolves, no country filtering happens at all.
  Future<void> _resolveMyCountry(LatLng loc) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt * 2));
      final code = await countryCodeFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (!mounted) return;
      if (code != null) {
        debugPrint(
          '[GigMap] resolved worker country: $code (from ${loc.latitude}, ${loc.longitude})',
        );
        setState(() => _myCountryCode = code);
        return;
      }
    }
    debugPrint(
      '[GigMap] could not resolve worker\'s own country after retries',
    );
  }

  // Queues gigs whose country isn't cached yet (grouped by a ~1km grid key so
  // nearby gigs share one lookup) onto a single shared queue, drained one at
  // a time to stay within Nominatim's rate limit regardless of how many of
  // the three gig streams triggered this at once.
  void _ensureCountriesResolved(List<GigMarkerData> gigs) {
    for (final g in gigs) {
      final key = _countryCacheKey(g.position.latitude, g.position.longitude);
      if (_countryCodeCache.containsKey(key) ||
          _resolvingCountryKeys.contains(key)) {
        continue;
      }
      _resolvingCountryKeys.add(key);
      _pendingCountryQueue.add(g);
    }
    _drainCountryQueue();
  }

  Future<void> _drainCountryQueue() async {
    if (_isResolvingCountries) return;
    _isResolvingCountries = true;
    try {
      while (_pendingCountryQueue.isNotEmpty) {
        final g = _pendingCountryQueue.removeAt(0);
        final key = _countryCacheKey(g.position.latitude, g.position.longitude);
        String? code;
        // A failed lookup is never cached (so it isn't permanently treated as
        // "unknown country" and left visible forever) — retry a few times
        // with backoff before giving up for this pass.
        for (var attempt = 0; attempt < 3 && code == null; attempt++) {
          if (attempt > 0) await Future.delayed(Duration(seconds: attempt * 2));
          code = await countryCodeFromCoordinates(
            g.position.latitude,
            g.position.longitude,
          );
        }
        _resolvingCountryKeys.remove(key);
        if (!mounted) return;
        final resolvedCode = code;
        if (resolvedCode != null) {
          debugPrint(
            '[GigMap] resolved gig ${g.id} (${g.title}) country: $resolvedCode',
          );
          setState(() => _countryCodeCache[key] = resolvedCode);
        } else {
          debugPrint(
            '[GigMap] country lookup failed for gig ${g.id}, will retry on next update',
          );
        }
        await Future.delayed(const Duration(milliseconds: 1100));
      }
    } finally {
      _isResolvingCountries = false;
    }
  }

  @override
  void didUpdateWidget(GigMapSection old) {
    super.didUpdateWidget(old);
  }

  void _startQuickSub(FirebaseFirestore db) {
    _quickSub = db
        .collection('quick_gigs')
        .where('status', whereIn: ['scanning', 'in_progress'])
        .snapshots()
        .listen((s) {
          final all = s.docs
              .map((d) {
                final data = d.data();
                final status = data['status'] as String? ?? '';
                if (status == 'in_progress' &&
                    data['assignedWorkerId'] != widget.uid) {
                  return null;
                }
                return _toMarker(d.id, data, 'quick');
              })
              .whereType<GigMarkerData>()
              .toList();
          setState(() => _quickGigs = all);
          _ensureCountriesResolved(all);
        }, onError: (e) => debugPrint('[GigMap] quick stream error: $e'));
  }

  void _startOpenSub(FirebaseFirestore db) {
    _openSub = db
        .collection('open_gigs')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((s) {
          final all = s.docs
              .where((d) => (d.data()['hostId'] as String?) != widget.uid)
              .map(
                (d) => _toMarker(d.id, d.data(), 'open', workerUid: widget.uid),
              )
              .whereType<GigMarkerData>()
              .toList();
          setState(() => _openGigs = all);
          _ensureCountriesResolved(all);
        }, onError: (e) => debugPrint('[GigMap] open stream error: $e'));
  }

  void _startOfferedSub(FirebaseFirestore db) {
    _offeredSub = db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen((s) {
          final all = s.docs
              .map((d) => _toMarker(d.id, d.data(), 'offered'))
              .whereType<GigMarkerData>()
              .toList();
          setState(() => _offeredGigs = all);
          _ensureCountriesResolved(all);
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This gig no longer exists.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final currentStatus = snap.data()?['status'] as String? ?? '';
      if (currentStatus != 'open') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gig is no longer available (status: $currentStatus).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Prevent double-apply
      final existing = List<dynamic>.from(snap.data()?['applicants'] ?? []);
      final alreadyApplied = existing.any(
        (a) => (a as Map<String, dynamic>)['workerId'] == widget.uid,
      );
      if (alreadyApplied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already applied to this gig.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
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

      // Notify the host — fire-and-forget so a failure doesn't block the apply flow
      unawaited(
        FirebaseFirestore.instance.collection('notifications').add({
          'userId': gig.hostId,
          'category': 'new_applicant',
          'message': '${widget.workerName} applied to your gig "${gig.title}"',
          'workerName': widget.workerName,
          'workerId': widget.uid,
          'gigId': gig.id,
          'gigTitle': gig.title,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Application submitted! Waiting for host selection.'),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[GigMap] apply to open gig error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _googleMapController?.dispose();
    _osmController.dispose();
    _quickSub?.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  GigMarkerData? _toMarker(
    String id,
    Map<String, dynamic> data,
    String type, {
    String workerUid = '',
  }) {
    final geo = data['location'] as GeoPoint?;
    if (geo == null) return null;
    final applicants = List<dynamic>.from(data['applicants'] ?? []);
    final hasApplied =
        type == 'open' &&
        workerUid.isNotEmpty &&
        applicants.any(
          (a) => (a as Map<String, dynamic>)['workerId'] == workerUid,
        );
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
      scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
      currencyCode: (data['currencyCode'] as String?) ?? 'PHP',
    );
  }

  List<GigMarkerData> get _unfilteredGigs => [
    ..._quickGigs,
    ..._openGigs,
    ..._offeredGigs,
  ];

  bool _matchesSkill(String skill, String other) =>
      skill.toLowerCase().trim() == other.toLowerCase().trim();

  List<GigMarkerData> get _allGigs {
    var gigs = _unfilteredGigs;

    switch (_skillFilter) {
      case _SkillFilter.all:
        break;
      case _SkillFilter.mySkills:
        gigs = gigs
            .where(
              (g) =>
                  g.requiredSkills.isEmpty ||
                  g.requiredSkills.any(
                    (s) =>
                        widget.workerSkills.any((ws) => _matchesSkill(ws, s)),
                  ),
            )
            .toList();
      case _SkillFilter.specific:
        final skill = _specificSkill;
        if (skill != null) {
          gigs = gigs
              .where(
                (g) => g.requiredSkills.any((s) => _matchesSkill(s, skill)),
              )
              .toList();
        }
    }

    final myLoc = _myLocation;
    final myCountry = _myCountryCode;
    if (myCountry != null) {
      gigs = gigs.where((g) {
        final key = _countryCacheKey(g.position.latitude, g.position.longitude);
        final gigCountry = _countryCodeCache[key];
        // Not resolved yet — keep it visible rather than hiding it while we wait.
        return gigCountry == null || gigCountry == myCountry;
      }).toList();
    }

    final radiusKm = _radiusKm;
    if (radiusKm != null && myLoc != null) {
      gigs = gigs.where((g) {
        final distM = Geolocator.distanceBetween(
          myLoc.latitude,
          myLoc.longitude,
          g.position.latitude,
          g.position.longitude,
        );
        return distM <= radiusKm * 1000;
      }).toList();
    }

    return gigs;
  }

  bool get _hasActiveFilter =>
      _skillFilter != _SkillFilter.all || _radiusKm != null;

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

  double _hueForType(String type) {
    switch (type) {
      case 'open':
        return BitmapDescriptor.hueBlue;
      case 'offered':
        return BitmapDescriptor.hueViolet;
      default:
        return BitmapDescriptor.hueYellow;
    }
  }

  List<Marker> _buildGoogleMarkers() {
    final markers = _buildClusters().map((cluster) {
      if (cluster.count == 1 && cluster.singleGig != null) {
        final singleGig = cluster.singleGig!;
        return Marker(
          markerId: MarkerId(singleGig.id),
          position: cluster.center,
          icon: _gigIcon(singleGig.gigType),
          onTap: () {
            final ctx = _context;
            if (ctx != null) _showGigSheet(ctx, singleGig);
          },
        );
      }

      return Marker(
        markerId: MarkerId(
          'cluster_${cluster.center.latitude}_${cluster.center.longitude}',
        ),
        position: cluster.center,
        icon: _resolveClusterIcon(cluster.count),
        onTap: () {
          final ctx = _context;
          if (ctx != null) _showClusterSheet(ctx, cluster.gigs);
        },
      );
    }).toList();

    if (_myLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon:
              _icons['location'] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: widget.workerName.isNotEmpty
                ? widget.workerName
                : 'Your Location',
          ),
          zIndex: 10,
        ),
      );
    }

    return markers;
  }

  ll.LatLng _toLL(LatLng pos) => ll.LatLng(pos.latitude, pos.longitude);

  Color _colorForType(String type) {
    switch (type) {
      case 'open':
        return kBlue;
      case 'offered':
        return const Color(0xFF8B5CF6);
      default:
        return kAmber;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'open':
        return Icons.workspace_premium_outlined;
      case 'offered':
        return Icons.send_rounded;
      default:
        return Icons.flash_on_rounded;
    }
  }

  Widget _buildOsmMap() {
    final clusters = _buildClusters();
    final osmMarkers = <fm.Marker>[];
    for (final cluster in clusters) {
      if (cluster.count == 1 && cluster.singleGig != null) {
        final gig = cluster.singleGig!;
        final color = _colorForType(gig.gigType);
        osmMarkers.add(
          fm.Marker(
            point: _toLL(cluster.center),
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () {
                final ctx = _context;
                if (ctx != null) _showGigSheet(ctx, gig);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Icon(
                  _iconForType(gig.gigType),
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        );
      } else {
        osmMarkers.add(
          fm.Marker(
            point: _toLL(cluster.center),
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () {
                final ctx = _context;
                if (ctx != null) _showClusterSheet(ctx, cluster.gigs);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${cluster.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    if (_myLocation != null) {
      osmMarkers.add(
        fm.Marker(
          point: _toLL(_myLocation!),
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.cyan,
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
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: _myLocation != null
            ? _toLL(_myLocation!)
            : const ll.LatLng(14.5995, 120.9842),
        initialZoom: _zoom,
        onMapReady: () {
          if (mounted) setState(() => _osmMapReady = true);
        },
        onPositionChanged: (camera, _) {
          final newZoom = camera.zoom;
          if ((newZoom - _zoom).abs() >= 0.3) setState(() => _zoom = newZoom);
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.mobile',
        ),
        fm.MarkerLayer(markers: osmMarkers),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Bottom sheet: single gig
  // ─────────────────────────────────────────────────────────────────────────
  void _showGigSheet(BuildContext context, GigMarkerData gig) {
    Color pinColor;
    switch (gig.gigType) {
      case 'open':
        pinColor = kBlue;
        break;
      case 'offered':
        pinColor = const Color(0xFF8B5CF6);
        break;
      default:
        pinColor = kAmber;
    }

    IconData pinIcon;
    switch (gig.gigType) {
      case 'open':
        pinIcon = Icons.workspace_premium_outlined;
        break;
      case 'offered':
        pinIcon = Icons.send_rounded;
        break;
      default:
        pinIcon = Icons.flash_on_rounded;
    }

    List<String> missingSkills() {
      if (gig.gigType != 'open' || gig.requiredSkills.isEmpty) return [];
      return gig.requiredSkills
          .where(
            (s) => !widget.workerSkills.any(
              (ws) => ws.toLowerCase().trim() == s.toLowerCase().trim(),
            ),
          )
          .toList();
    }

    _openMarkerSheet(context, (ctx) {
      final cardColor = Theme.of(ctx).cardColor;
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      final color = pinColor;
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
      final missing = missingSkills();
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
                  child: Icon(pinIcon, color: color, size: 22),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
              value: CurrencyFormatter.format(gig.budget, gig.currencyCode),
              valueColor: kAmber,
            ),
            if (gig.scheduledDate != null)
              _GigSheetRow(
                icon: Icons.calendar_today_rounded,
                label: 'Schedule',
                value: DateFormat(
                  'EEE, MMM d • h:mm a',
                ).format(gig.scheduledDate!),
              ),
            if (gig.address.isNotEmpty)
              _GigSheetRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: gig.address,
                maxLines: null,
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
                  const Icon(Icons.construction_rounded, color: kSub, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Skills: ',
                    style: TextStyle(color: kSub, fontSize: 13),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: gig.requiredSkills.map((s) {
                        final has = widget.workerSkills.any(
                          (ws) =>
                              ws.toLowerCase().trim() == s.toLowerCase().trim(),
                        );
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: has
                                ? const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.12)
                                : Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: has
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.4)
                                  : Colors.red.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                has
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                size: 11,
                                color: has
                                    ? const Color(0xFF10B981)
                                    : Colors.red,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                s,
                                style: TextStyle(
                                  color: has
                                      ? const Color(0xFF10B981)
                                      : Colors.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.red,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You lack ${missing.length == 1 ? 'a required skill' : '${missing.length} required skills'}: ${missing.join(', ')}',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
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
                        if (widget.isVerified != 'verified') {
                          _showModal(context);
                          return;
                        }
                        Navigator.pop(ctx);
                        if (gig.gigType == 'quick') {
                          widget.onQuickGigStarted?.call(gig);
                        } else if (gig.gigType == 'open') {
                          _applyToOpenGig(gig);
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAppliedPending) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      isAppliedPending
                          ? 'Application Pending'
                          : canApply
                          ? btnLabel
                          : 'Skills Required',
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
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Bottom sheet: cluster list
  // ─────────────────────────────────────────────────────────────────────────
  void _showClusterSheet(BuildContext context, List<GigMarkerData> gigs) {
    _openMarkerSheet(context, (ctx) {
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
                    child: const Icon(
                      Icons.work_outline_rounded,
                      color: kAmber,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${gigs.length} Gigs in this area',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Tap a gig to see details',
                        style: TextStyle(color: kSub, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(
              color: isDark
                  ? kBorder.withValues(alpha: 0.5)
                  : Colors.grey.withValues(alpha: 0.15),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: gigs.length,
                separatorBuilder: (_, i) => Divider(
                  height: 1,
                  color: isDark
                      ? kBorder.withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.1),
                ),
                itemBuilder: (_, i) {
                  final g = gigs[i];
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
                  final missing =
                      g.gigType == 'open' && g.requiredSkills.isNotEmpty
                      ? g.requiredSkills
                            .where(
                              (s) => !widget.workerSkills.any(
                                (ws) =>
                                    ws.toLowerCase().trim() ==
                                    s.toLowerCase().trim(),
                              ),
                            )
                            .toList()
                      : <String>[];
                  final canApply = missing.isEmpty;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(typeIcon, color: typeColor, size: 20),
                    ),
                    title: Text(
                      g.title,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  color: typeColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              CurrencyFormatter.format(g.budget, g.currencyCode),
                              style: const TextStyle(
                                color: kAmber,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (missing.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Missing: ${missing.join(', ')}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                            ),
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
                                _applyToOpenGig(g);
                              }
                            }
                          : null,
                      style: TextButton.styleFrom(
                        backgroundColor: canApply
                            ? typeColor.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        foregroundColor: canApply ? typeColor : Colors.grey,
                        disabledForegroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        canApply ? btnLabel : 'Locked',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }, isScrollControlled: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Filter sheet — skill + radius
  // ─────────────────────────────────────────────────────────────────────────
  static const List<double?> _radiusOptions = [null, 1, 5, 10, 50, 100];

  void _showFilterSheet(BuildContext context) {
    final skills = _allSkillNames;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget sectionTitle(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                text,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );

            Widget choiceChip({
              required String label,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? kAmber.withValues(alpha: 0.15)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? kAmber : Theme.of(ctx).dividerColor,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? kAmber : onSurface,
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: kAmber, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Filter Gigs',
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _skillFilter = _SkillFilter.all;
                              _specificSkill = null;
                              _radiusKm = null;
                            });
                            setState(() {
                              _skillFilter = _SkillFilter.all;
                              _specificSkill = null;
                              _radiusKm = null;
                            });
                          },
                          child: const Text(
                            'Reset',
                            style: TextStyle(color: kSub, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    sectionTitle('Show gigs'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choiceChip(
                          label: 'All Gigs',
                          selected: _skillFilter == _SkillFilter.all,
                          onTap: () {
                            setSheetState(
                              () => _skillFilter = _SkillFilter.all,
                            );
                            setState(() => _skillFilter = _SkillFilter.all);
                          },
                        ),
                        choiceChip(
                          label: 'Matches My Skills',
                          selected: _skillFilter == _SkillFilter.mySkills,
                          onTap: () {
                            setSheetState(
                              () => _skillFilter = _SkillFilter.mySkills,
                            );
                            setState(
                              () => _skillFilter = _SkillFilter.mySkills,
                            );
                          },
                        ),
                        choiceChip(
                          label: 'Specific Skill',
                          selected: _skillFilter == _SkillFilter.specific,
                          onTap: skills.isEmpty
                              ? () {}
                              : () {
                                  setSheetState(() {
                                    _skillFilter = _SkillFilter.specific;
                                    _specificSkill ??= skills.first;
                                  });
                                  setState(() {
                                    _skillFilter = _SkillFilter.specific;
                                    _specificSkill ??= skills.first;
                                  });
                                },
                        ),
                      ],
                    ),
                    if (_skillFilter == _SkillFilter.specific) ...[
                      const SizedBox(height: 12),
                      if (skills.isEmpty)
                        const Text(
                          'Loading skills…',
                          style: TextStyle(color: kSub, fontSize: 12),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(ctx).dividerColor,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: skills.contains(_specificSkill)
                                  ? _specificSkill
                                  : skills.first,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: kSub,
                              ),
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              dropdownColor: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              items: skills
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (s) {
                                if (s == null) return;
                                setSheetState(() => _specificSkill = s);
                                setState(() => _specificSkill = s);
                              },
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 18),
                    sectionTitle('Distance'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _radiusOptions.map((r) {
                        final label = r == null
                            ? 'Any'
                            : '${r.toStringAsFixed(0)} km';
                        return choiceChip(
                          label: label,
                          selected: _radiusKm == r,
                          onTap: () {
                            setSheetState(() => _radiusKm = r);
                            setState(() => _radiusKm = r);
                          },
                        );
                      }).toList(),
                    ),
                    if (_radiusKm != null && _myLocation == null) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Your location isn\'t available yet — distance filter will apply once located.',
                        style: TextStyle(color: kSub, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAmber,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    if (widget.fullScreen) return _buildFullScreenLayout(context);

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
              child: Text(
                'Gigs Near You',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (offeredCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$offeredCount Offered',
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                '$total ${total == 1 ? 'Gig' : 'Gigs'}',
                style: const TextStyle(
                  color: kGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showFilterSheet(context),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _hasActiveFilter
                      ? kAmber.withValues(alpha: 0.15)
                      : borderColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _hasActiveFilter
                        ? kAmber.withValues(alpha: 0.6)
                        : borderColor,
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: _hasActiveFilter ? kAmber : onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _LegendDot(color: kGold, label: 'Quick'),
            const SizedBox(width: 14),
            _LegendDot(color: kBlue, label: 'Open'),
            const SizedBox(width: 14),
            _LegendDot(color: const Color(0xFF8B5CF6), label: 'Offered to me'),
          ],
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: _useGoogleMaps
                    ? GoogleMap(
                        gestureRecognizers: _mapInteractive
                            ? <Factory<OneSequenceGestureRecognizer>>{
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              }
                            : const <Factory<OneSequenceGestureRecognizer>>{},
                        onMapCreated: (controller) {
                          _googleMapController = controller;
                          if (_myLocation != null) {
                            controller.animateCamera(
                              CameraUpdate.newLatLngZoom(_myLocation!, 14.0),
                            );
                          }
                        },
                        initialCameraPosition: const CameraPosition(
                          target: LatLng(14.5995, 120.9842),
                          zoom: 12.0,
                        ),
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        markers: Set<Marker>.from(_buildGoogleMarkers()),
                        onCameraMove: (position) {
                          final newZoom = position.zoom;
                          if ((newZoom - _zoom).abs() >= 0.3) {
                            setState(() => _zoom = newZoom);
                          }
                        },
                      )
                    : _buildOsmMap(),
              ),
            ),
            // Tap-to-interact overlay — blocks map from stealing scroll gestures
            if (!_mapInteractive)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _mapInteractive = true),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Tap to interact with map',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Lock-map button shown while map is interactive
            if (_mapInteractive)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _mapInteractive = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_open_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Tap to lock map',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
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
            // Fullscreen expand button
            Positioned(
              bottom: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => Scaffold(
                      body: GigMapSection(
                        fullScreen: true,
                        uid: widget.uid,
                        workerName: widget.workerName,
                        seekingQuickGigs: widget.seekingQuickGigs,
                        onQuickGigStarted: widget.onQuickGigStarted,
                        onOpenGigApplied: widget.onOpenGigApplied,
                        isVerified: widget.isVerified,
                        workerSkills: widget.workerSkills,
                      ),
                    ),
                  ),
                ),
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
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    size: 20,
                    color: kBlue,
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
            style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildFullScreenLayout(BuildContext ctx) {
    final total = _allGigs.length;
    final offeredCount = _offeredGigs.length;
    final topPad = MediaQuery.of(ctx).padding.top;
    final bottomPad = MediaQuery.of(ctx).padding.bottom;

    return Stack(
      children: [
        // Map fills entire scaffold body
        Positioned.fill(
          child: _useGoogleMaps
              ? GoogleMap(
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  onMapCreated: (c) {
                    _googleMapController = c;
                    if (_myLocation != null) {
                      c.animateCamera(
                        CameraUpdate.newLatLngZoom(_myLocation!, 14.0),
                      );
                    }
                  },
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(14.5995, 120.9842),
                    zoom: 12.0,
                  ),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: Set<Marker>.from(_buildGoogleMarkers()),
                  onCameraMove: (pos) {
                    if ((pos.zoom - _zoom).abs() >= 0.3) {
                      setState(() => _zoom = pos.zoom);
                    }
                  },
                )
              : _buildOsmMap(),
        ),

        // Top bar: close + title + count pill
        Positioned(
          top: topPad + 8,
          left: 12,
          right: 12,
          child: Row(
            children: [
              // Close button
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).cardColor,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: const Icon(Icons.close_rounded, size: 18, color: kSub),
                ),
              ),
              const SizedBox(width: 8),
              // Title pill
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).cardColor.withValues(alpha: 0.93),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: const Text(
                    'Gigs Near You',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Total count pill
              if (offeredCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Text(
                    '$offeredCount Offered',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: Text(
                  '$total ${total == 1 ? 'Gig' : 'Gigs'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showFilterSheet(ctx),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _hasActiveFilter
                        ? kAmber.withValues(alpha: 0.92)
                        : Theme.of(ctx).cardColor.withValues(alpha: 0.93),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _hasActiveFilter ? Colors.white : kSub,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Legend (bottom-left)
        Positioned(
          bottom: bottomPad + 20,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor.withValues(alpha: 0.93),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LegendDot(color: kGold, label: 'Quick'),
                const SizedBox(height: 6),
                const _LegendDot(color: kBlue, label: 'Open'),
                if (offeredCount > 0) ...[
                  const SizedBox(height: 6),
                  const _LegendDot(
                    color: Color(0xFF8B5CF6),
                    label: 'Offered to me',
                  ),
                ],
              ],
            ),
          ),
        ),

        // Recenter button (bottom-right)
        Positioned(
          bottom: bottomPad + 20,
          right: 12,
          child: GestureDetector(
            onTap: _fetchAndCenterMap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
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
                size: 20,
                color: _myLocation != null ? kBlue : kSub,
              ),
            ),
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: kSub, fontSize: 11)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig sheet row
// ─────────────────────────────────────────────────────────────────────────────
class _GigSheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final int? maxLines;
  const _GigSheetRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kSub, size: 16),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: kSub, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: maxLines,
              overflow: maxLines == null
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Verification modal
// ─────────────────────────────────────────────────────────────────────────────
void _showModal(BuildContext context) {
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
              color: (Colors.red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Account not Verified',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                backgroundColor: Colors.red,
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
