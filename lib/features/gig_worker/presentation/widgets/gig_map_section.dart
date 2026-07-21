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
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/map_style.dart';
import '../../../../core/services/gms_availability.dart';
import '../../../../core/utils/country_check.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/worker_active_gig.dart';

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
  final DateTime? createdAt;
  final int applicantCount;

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
    this.createdAt,
    this.applicantCount = 0,
  });
}

enum _SkillFilter { all, mySkills, specific }

enum _GigViewMode { map, list }

const String _kGigsViewModePrefKey = 'gigs_view_mode';

// Rounds a coordinate to a ~1km grid so nearby gigs share one reverse-geocode
// lookup instead of firing one per gig.
String _countryCacheKey(double lat, double lng) =>
    '${(lat * 100).round()},${(lng * 100).round()}';

// Gigs-near-you list surfaces (search bar, gig cards, empty/skeleton states)
// sit on top of the dashboard's own card-colored container in dark mode, so
// using Theme.cardColor directly makes them blend in — a bit brighter than
// kCard so each card reads as distinct from the section around it.
Color _listSurfaceColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF2A3B52) : Theme.of(context).cardColor;
}

// Flat neutral chip/row background (icon containers, skill chips, the "see
// on map" row, the disabled Apply state) — near-white on light, a subtle
// light-on-dark tint in dark mode instead of the hardcoded #F1F5F9-family
// hex values that stayed invisible-bright regardless of theme.
Color _neutralSurface(bool isDark) =>
    isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);

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
  // Set by the gig sheet's "see on map" row when opened from list mode, so the
  // map centers on that gig instead of the worker's own location the next
  // time it mounts. Consumed once in onMapCreated, then cleared.
  LatLng? _pendingCameraTarget;
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

  // Whether each gig stream has delivered its first snapshot yet — used to
  // show a loading state in list mode instead of a premature "no gigs" empty
  // state while the initial Firestore reads are still in flight.
  bool _quickLoaded = false;
  bool _openLoaded = false;
  bool _offeredLoaded = false;
  bool get _gigsStillLoading =>
      !(_quickLoaded && _openLoaded && _offeredLoaded);

  StreamSubscription? _quickSub;
  late StreamSubscription _openSub, _offeredSub;

  // ── Country matching (only show gigs in the worker's own country) ─────────
  String? _myCountryCode;
  final Map<String, String> _countryCodeCache = {};
  final Set<String> _resolvingCountryKeys = {};
  final List<GigMarkerData> _pendingCountryQueue = [];
  bool _isResolvingCountries = false;

  // ── Filters ──────────────────────────────────────────────────────────────
  // Defaults: match the worker's own skills, within 10km.
  _SkillFilter _skillFilter = _SkillFilter.mySkills;
  String? _specificSkill;
  double? _radiusKm = 10; // null = no radius limit
  List<String> _allSkillNames = [];

  // ── Map/List view toggle (compact section only) ────────────────────────
  _GigViewMode _viewMode = _GigViewMode.map;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  static const int _kListPageSize = 10;
  int _visibleListCount = _kListPageSize;

  Future<void> _loadSavedViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kGigsViewModePrefKey);
      if (saved == _GigViewMode.list.name && mounted) {
        setState(() => _viewMode = _GigViewMode.list);
      }
    } catch (_) {}
  }

  void _setViewMode(_GigViewMode mode) {
    if (mode == _viewMode) return;
    setState(() => _viewMode = mode);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_kGigsViewModePrefKey, mode.name))
        .catchError((_) => false);
  }

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
    if (!widget.fullScreen) _loadSavedViewMode();
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
        .listen(
          (s) {
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
            setState(() {
              _quickGigs = all;
              _quickLoaded = true;
            });
            _ensureCountriesResolved(all);
          },
          onError: (e) {
            debugPrint('[GigMap] quick stream error: $e');
            if (mounted) setState(() => _quickLoaded = true);
          },
        );
  }

  void _startOpenSub(FirebaseFirestore db) {
    _openSub = db
        .collection('open_gigs')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen(
          (s) {
            final all = s.docs
                .where((d) => (d.data()['hostId'] as String?) != widget.uid)
                .map(
                  (d) =>
                      _toMarker(d.id, d.data(), 'open', workerUid: widget.uid),
                )
                .whereType<GigMarkerData>()
                .toList();
            setState(() {
              _openGigs = all;
              _openLoaded = true;
            });
            _ensureCountriesResolved(all);
          },
          onError: (e) {
            debugPrint('[GigMap] open stream error: $e');
            if (mounted) setState(() => _openLoaded = true);
          },
        );
  }

  void _startOfferedSub(FirebaseFirestore db) {
    _offeredSub = db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen(
          (s) {
            final all = s.docs
                .map((d) => _toMarker(d.id, d.data(), 'offered'))
                .whereType<GigMarkerData>()
                .toList();
            setState(() {
              _offeredGigs = all;
              _offeredLoaded = true;
            });
            _ensureCountriesResolved(all);
          },
          onError: (e) {
            debugPrint('[GigMap] offered stream error: $e');
            if (mounted) setState(() => _offeredLoaded = true);
          },
        );
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

      if (await workerHasActiveGig(widget.uid)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You need to finish your current gig before applying to another one.',
              ),
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
    _searchController.dispose();
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      applicantCount: type == 'open' ? applicants.length : 0,
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
  void _showGigSheet(
    BuildContext context,
    GigMarkerData gig, {
    bool fromList = false,
  }) {
    final accent = _cardAccentForType(gig.gigType);
    final statusLabel = _typeLabel(gig.gigType);

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

    String timeAgo(DateTime dt) {
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    }

    // Collapses immediate consecutive duplicate comma-separated parts (e.g.
    // "Foo St, Foo St, City" -> "Foo St, City") — display only.
    String dedupAddress(String address) {
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

    final missing = missingSkills();
    final canApply = missing.isEmpty;
    final isAppliedPending = gig.gigType == 'open' && gig.hasApplied;
    final canTapApply = canApply && !isAppliedPending;

    final distanceM = _myLocation != null
        ? Geolocator.distanceBetween(
            _myLocation!.latitude,
            _myLocation!.longitude,
            gig.position.latitude,
            gig.position.longitude,
          )
        : null;
    final locationLabel = distanceM != null
        ? 'LOCATION · ${_fmtDistance(distanceM).toUpperCase()}'
        : 'LOCATION';

    _openMarkerSheet(context, (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      final neutralSurface = _neutralSurface(isDark);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 16 + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 14),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? kBorder : const Color(0xFFD5DCE6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Title row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        gig.title,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (gig.createdAt != null)
                  Text(
                    gig.applicantCount > 0
                        ? 'Posted ${timeAgo(gig.createdAt!)} · ${gig.applicantCount} ${gig.applicantCount == 1 ? 'applicant' : 'applicants'} so far'
                        : 'Posted ${timeAgo(gig.createdAt!)}',
                    style: const TextStyle(color: kSub, fontSize: 11),
                  ),
                const SizedBox(height: 16),
                // Host row (display only)
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        gig.hostName.isNotEmpty
                            ? gig.hostName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: kBlue,
                          fontSize: 14,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          FutureBuilder<double?>(
                            future: _fetchHostRating(gig.hostId),
                            builder: (context, snap) {
                              final rating = snap.data;
                              if (rating == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: kSub,
                                      fontSize: 10.5,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: '★ ',
                                        style: TextStyle(
                                          color: Color(0xFFF0A830),
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            '${rating.toStringAsFixed(1)} host rating',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 0,
                  thickness: 1,
                  color: Theme.of(ctx).dividerColor,
                ),
                const SizedBox(height: 14),
                // Info grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _InfoGridCell(
                        label: 'PAY',
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: CurrencyFormatter.format(
                                  gig.budget,
                                  gig.currencyCode,
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF2B6FB5),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(
                                text: ' / day',
                                style: TextStyle(color: kSub, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoGridCell(
                        icon: Icons.calendar_today_rounded,
                        label: 'SCHEDULE',
                        value: gig.scheduledDate != null
                            ? DateFormat(
                                'EEE, MMM d · h:mm a',
                              ).format(gig.scheduledDate!)
                            : '—',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _InfoGridCell(
                        icon: Icons.location_on_outlined,
                        label: locationLabel,
                        value: gig.address.isNotEmpty
                            ? dedupAddress(gig.address)
                            : '—',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoGridCell(
                        icon: Icons.bar_chart_rounded,
                        label: 'EXPERIENCE',
                        value: gig.experienceLevel.isNotEmpty
                            ? gig.experienceLevel
                            : '—',
                      ),
                    ),
                  ],
                ),
                if (gig.requiredSkills.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'SKILLS NEEDED',
                    style: TextStyle(
                      color: kSub,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: gig.requiredSkills.map((s) {
                      final has = widget.workerSkills.any(
                        (ws) =>
                            ws.toLowerCase().trim() == s.toLowerCase().trim(),
                      );
                      return Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: has
                              ? const Color(0xFF2E9E6B).withValues(alpha: 0.12)
                              : neutralSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            color: has ? const Color(0xFF2E9E6B) : kSub,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
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
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.25),
                        ),
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
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                // See on map row
                GestureDetector(
                  onTap: () {
                    if (fromList) {
                      _pendingCameraTarget = gig.position;
                      _setViewMode(_GigViewMode.map);
                    }
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: neutralSurface,
                      border: Border.all(color: Theme.of(ctx).dividerColor),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.map_outlined, size: 18, color: kSub),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'See this gig on the map',
                            style: TextStyle(
                              color: kSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: kSub,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Apply button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: canTapApply
                          ? const LinearGradient(
                              colors: [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
                            )
                          : null,
                      color: canTapApply ? null : neutralSurface,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: canTapApply
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
                        child: Center(
                          child: Text(
                            isAppliedPending ? 'Application sent' : 'Apply now',
                            style: TextStyle(
                              color: canTapApply ? Colors.white : kSub,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (gig.gigType == 'open') ...[
                  const SizedBox(height: 10),
                  const Text(
                    "You can withdraw your application anytime before it's accepted",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSub, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }, isScrollControlled: true);
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
                              CurrencyFormatter.format(
                                g.budget,
                                g.currencyCode,
                              ),
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

  static const Color _kSegActiveBg = Color(0xFF1F4D80);
  static const Color _kCardBorder = Color(0xFFE4E9F0);
  static const Color _kQuickDot = Color(0xFFF0A830);
  static const Color _kOpenDot = Color(0xFF2B6FB5);
  static const Color _kOfferedDot = Color(0xFF8B6FD8);

  Widget _buildViewModeToggle() {
    return Container(
      width: 110,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(child: _buildViewModeSegment(_GigViewMode.map, 'Map')),
          Expanded(child: _buildViewModeSegment(_GigViewMode.list, 'List')),
        ],
      ),
    );
  }

  Widget _buildViewModeSegment(_GigViewMode mode, String label) {
    final active = _viewMode == mode;
    return GestureDetector(
      onTap: () => _setViewMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _kSegActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : kSub,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterButton(BuildContext context, {required Color onSurface}) {
    final borderColor = Theme.of(context).dividerColor;
    return GestureDetector(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    if (widget.fullScreen) return _buildFullScreenLayout(context);

    final onSurface = Theme.of(context).colorScheme.onSurface;
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
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0A830).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$total ${total == 1 ? 'Gig' : 'Gigs'}',
                style: const TextStyle(
                  color: Color(0xFFB06E00),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _buildViewModeToggle(),
            const SizedBox(width: 8),
            _buildFilterButton(context, onSurface: onSurface),
          ],
        ),
        const SizedBox(height: 12),
        if (_viewMode == _GigViewMode.map)
          _buildMapBlock(context)
        else
          _buildListMode(context),
      ],
    );
  }

  Widget _buildMapBlock(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 332,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kCardBorder),
            ),
            child: _useGoogleMaps
                ? GoogleMap(
                    style: Theme.of(context).brightness == Brightness.dark
                        ? kDarkMapStyle
                        : null,
                    gestureRecognizers: _mapInteractive
                        ? <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          }
                        : const <Factory<OneSequenceGestureRecognizer>>{},
                    onMapCreated: (controller) {
                      _googleMapController = controller;
                      final pending = _pendingCameraTarget;
                      final target = pending ?? _myLocation;
                      if (target != null) {
                        // A pending target came from "See this gig on the
                        // map" — zoom in past the clustering grid (see
                        // _gridSize) so this specific gig renders as its own
                        // pin instead of staying grouped into a cluster.
                        final zoom = pending != null ? 19.0 : 14.0;
                        controller.animateCamera(
                          CameraUpdate.newLatLngZoom(target, zoom),
                        );
                        if (pending != null) {
                          setState(() => _zoom = zoom);
                        }
                      }
                      _pendingCameraTarget = null;
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
        // Legend overlay chip — same info as the old standalone legend row
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendChipDot(_kQuickDot, 'Quick'),
                const SizedBox(width: 8),
                _legendChipDot(_kOpenDot, 'Open'),
                const SizedBox(width: 8),
                _legendChipDot(_kOfferedDot, 'Offered'),
              ],
            ),
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
                          style: TextStyle(color: Colors.white, fontSize: 11),
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
        // "Tap a pin for details" hint — moved onto the map as a bottom-center
        // overlay chip (bottom-left/right are already the expand/recenter buttons).
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tap a pin for details',
                  style: TextStyle(color: Colors.white, fontSize: 10.5),
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
    );
  }

  Widget _legendChipDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF5A6778), fontSize: 9.5),
        ),
      ],
    );
  }

  Color _cardAccentForType(String type) {
    switch (type) {
      case 'open':
        return _kOpenDot;
      case 'offered':
        return _kOfferedDot;
      default:
        return _kQuickDot;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'open':
        return 'Open';
      case 'offered':
        return 'Offered';
      default:
        return 'Quick';
    }
  }

  Widget _buildListMode(BuildContext context) {
    final gigs = _allGigs;
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? gigs
        : gigs
              .where(
                (g) =>
                    g.title.toLowerCase().contains(query) ||
                    g.hostName.toLowerCase().contains(query),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _listSurfaceColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 18, color: kSub),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() {
                    _searchQuery = v;
                    _visibleListCount = _kListPageSize;
                  }),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'Search gigs near you',
                    hintStyle: TextStyle(color: kSub, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_gigsStillLoading)
          Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                const _GigListCardSkeleton(),
                const SizedBox(height: 10),
              ],
            ],
          )
        else if (gigs.isEmpty)
          _emptyListCard('No gigs nearby right now')
        else if (filtered.isEmpty)
          _emptyListCard("No gigs match '${_searchQuery.trim()}'")
        else ...[
          Column(
            children: [
              for (final gig in filtered.take(_visibleListCount)) ...[
                _GigListCard(
                  gig: gig,
                  accentColor: _cardAccentForType(gig.gigType),
                  typeLabel: _typeLabel(gig.gigType),
                  distanceLabel: _myLocation != null
                      ? _fmtDistance(
                          Geolocator.distanceBetween(
                            _myLocation!.latitude,
                            _myLocation!.longitude,
                            gig.position.latitude,
                            gig.position.longitude,
                          ),
                        )
                      : null,
                  onTap: () => _showGigSheet(context, gig, fromList: true),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
          if (_visibleListCount < filtered.length)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _visibleListCount += _kListPageSize),
                child: const Text(
                  'See more',
                  style: TextStyle(
                    color: Color(0xFF2B6FB5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _fmtDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  // Same field the host's own profile screen reads
  // (gig_host_profile_screen.dart) — one doc read, shown on the gig sheet's
  // host row. Gracefully returns null (hidden) on any failure.
  Future<double?> _fetchHostRating(String hostId) async {
    if (hostId.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(hostId)
          .get();
      final rating = (doc.data()?['ratingAsHost'] as num?)?.toDouble();
      return rating;
    } catch (_) {
      return null;
    }
  }

  Widget _emptyListCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _listSurfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kSub, fontSize: 12.5),
      ),
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
                  style: Theme.of(context).brightness == Brightness.dark
                      ? kDarkMapStyle
                      : null,
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
//  List-mode loading placeholder — shown while the gig streams' first
//  snapshot is still in flight, so it doesn't flash "No gigs nearby" first.
// ─────────────────────────────────────────────────────────────────────────────
class _GigListCardSkeleton extends StatefulWidget {
  const _GigListCardSkeleton();

  @override
  State<_GigListCardSkeleton> createState() => _GigListCardSkeletonState();
}

class _GigListCardSkeletonState extends State<_GigListCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar({required double width, required double height}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: kSub.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.4, end: 1.0)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _listSurfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _bar(width: 140, height: 12),
                _bar(width: 40, height: 10),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _bar(width: 90, height: 10),
                _bar(width: 56, height: 14),
              ],
            ),
            const SizedBox(height: 8),
            _bar(width: 180, height: 9),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  List-mode gig card — same tap target/behavior as a map pin (_showGigSheet).
// ─────────────────────────────────────────────────────────────────────────────
class _GigListCard extends StatelessWidget {
  final GigMarkerData gig;
  final Color accentColor;
  final String typeLabel;
  final String? distanceLabel;
  final VoidCallback onTap;

  const _GigListCard({
    required this.gig,
    required this.accentColor,
    required this.typeLabel,
    required this.onTap,
    this.distanceLabel,
  });

  // Addresses are stored as full "street, barangay/municipality, province"
  // strings — the card only has room for the municipality + province, so
  // keep just the last two comma-separated segments for display.
  static String _summarizeAddress(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 2) return parts.join(', ');
    return parts.sublist(parts.length - 2).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final scheduleText = gig.scheduledDate != null
        ? DateFormat('EEE, h:mm a').format(gig.scheduledDate!)
        : null;
    final metaParts = [
      if (gig.address.isNotEmpty) _summarizeAddress(gig.address),
      ?scheduleText,
      ?distanceLabel,
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _listSurfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: title ── type badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    gig.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Row 2: host name ── pay
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    gig.hostName.isNotEmpty ? gig.hostName : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kSub, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: CurrencyFormatter.format(
                          gig.budget,
                          gig.currencyCode,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF2B6FB5),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(
                        text: '/day',
                        style: TextStyle(
                          color: kSub,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Row 3: location · schedule · distance ── chevron
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 13, color: kSub),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    metaParts.isNotEmpty ? metaParts.join(' · ') : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kSub, fontSize: 10.5),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 18, color: kSub),
              ],
            ),
          ],
        ),
      ),
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
//  Gig detail sheet — 2x2 info grid cell (icon + micro-label + value)
// ─────────────────────────────────────────────────────────────────────────────
class _InfoGridCell extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? value;
  final Widget? child;
  const _InfoGridCell({
    this.icon,
    required this.label,
    this.value,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _neutralSurface(isDark),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: kSub),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kSub,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              child ??
                  Text(
                    value ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ],
          ),
        ),
      ],
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
