import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:giggre_app/core/constants/api_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/gms_availability.dart';
import '../../../core/utils/country_check.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/map_style.dart';
import '../../../core/providers/current_user_provider.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/gig_template_model.dart';
import '../models/offered_gig_model.dart';
import '../models/worker_slot_model.dart';
import 'widgets/template_name_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Experience level options
// ─────────────────────────────────────────────────────────────────────────────
const _kLevels = [
  ('entry', 'Entry Level', 'No prior experience needed'),
  ('intermediate', 'Intermediate', '1–3 years of experience'),
  ('expert', 'Expert', '3+ years of experience'),
];

const _kPurple = Color(0xFF8B5CF6);

// ─────────────────────────────────────────────────────────────────────────────
//  Worker data model for picker
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerEntry {
  final String uid; // Firebase Auth UID (Firestore doc ID)
  final String userId; // Custom human-readable ID e.g. "YSJ135610"
  final String name;
  final String email;
  final double rating;
  final int ratingCount;
  final int completedGigs;
  const _WorkerEntry({
    required this.uid,
    required this.userId,
    required this.name,
    required this.email,
    this.rating = 5.0,
    this.ratingCount = 0,
    this.completedGigs = 0,
  });
}

// Counts a worker's completed gigs across all gig collections.
Future<int> _fetchCompletedGigsCount(String workerId) async {
  final db = FirebaseFirestore.instance;
  int count = 0;
  for (final col in ['quick_gigs', 'open_gigs', 'offered_gigs']) {
    final snap = await db
        .collection(col)
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get();
    count += snap.docs.length;
  }
  return count;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Post Offered Gig Screen
// ─────────────────────────────────────────────────────────────────────────────
class PostOfferedGigScreen extends StatefulWidget {
  final String hostName;
  final GigTemplateModel? template;
  final String? preselectedWorkerId;
  final String? preselectedWorkerName;
  const PostOfferedGigScreen({
    super.key,
    required this.hostName,
    this.template,
    this.preselectedWorkerId,
    this.preselectedWorkerName,
  });

  @override
  State<PostOfferedGigScreen> createState() => _PostOfferedGigScreenState();
}

class _PostOfferedGigScreenState extends State<PostOfferedGigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  // Worker selection — multiple workers can be offered the same gig, each
  // independently accepting/declining and settling on their own timeline.
  List<_WorkerEntry> _selectedWorkers = [];
  Map<String, int> _workerSkillsXP = {};
  bool _loadingWorkerSkills = false;

  // Skill (loaded from worker's skillsXP)
  String? _selectedSkill;

  // Experience level
  String _experienceLevel = 'entry';

  // Schedule
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  // Location
  Position? _gpsPosition;
  LatLng? _mapPosition;
  String _address = '';
  String _gpsAddress = '';
  bool _loadingLocation = false;
  String? _locationError;
  bool _useMapLocation = false;

  bool _posting = false;
  final _errorPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _fetchGpsLocation();
    final t = widget.template;
    if (t != null) {
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description;
      if (t.budget > 0) _budgetCtrl.text = t.budget.toStringAsFixed(0);
      if (t.skillRequired.isNotEmpty) _selectedSkill = t.skillRequired;
      if (t.experienceLevel.isNotEmpty) _experienceLevel = t.experienceLevel;
    }
    final preId = widget.preselectedWorkerId;
    if (preId != null && preId.isNotEmpty) {
      _preloadWorker(preId, widget.preselectedWorkerName ?? '');
    }
  }

  Future<void> _preloadWorker(String uid, String fallbackName) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      final data = doc.data();
      setState(() {
        _selectedWorkers = [
          _WorkerEntry(
            uid: uid,
            userId: data?['userId'] as String? ?? '',
            name: data?['name'] as String? ?? fallbackName,
            email: data?['email'] as String? ?? '',
          ),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedWorkers = [
          _WorkerEntry(uid: uid, userId: '', name: fallbackName, email: ''),
        ];
      });
    }
    _fetchWorkerSkills();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _errorPlayer.dispose();
    super.dispose();
  }

  // ── GPS ─────────────────────────────────────────────────────────────────────
  Future<void> _fetchGpsLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services disabled. Please enable GPS.';
          _loadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permission denied. Tap to retry.';
          _loadingLocation = false;
        });
        return;
      }

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // Save GPS position immediately — geocoding failure won't block submission
      if (!mounted) return;
      setState(() {
        _gpsPosition = pos;
        _loadingLocation = false;
      });

      String address = 'GPS location ready';
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(const Duration(seconds: 10));
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final hasName =
              p.name != null && p.name!.isNotEmpty && p.name != p.street;
          final parts = [
            if (hasName) p.name,
            if (p.street != null && p.street!.isNotEmpty) p.street,
            if (p.subLocality != null && p.subLocality!.isNotEmpty)
              p.subLocality,
            if (p.locality != null && p.locality!.isNotEmpty) p.locality,
            if (p.administrativeArea != null &&
                p.administrativeArea!.isNotEmpty)
              p.administrativeArea,
          ];
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _gpsAddress = address;
        if (!_useMapLocation) _address = address;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = 'Could not get location. Tap to retry.';
        _loadingLocation = false;
      });
    }
  }

  // ── Schedule pickers ─────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: _kPurple, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: _kPurple, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  // ── Map location picker ───────────────────────────────────────────────────────
  Future<void> _openMapPicker() async {
    final initial =
        _mapPosition ??
        (_gpsPosition != null
            ? LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude)
            : null);

    final result = await Navigator.push<_PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => _MapPickerScreen(initialPosition: initial),
      ),
    );

    if (result != null) {
      setState(() {
        _mapPosition = result.position;
        _address = result.address;
        _useMapLocation = true;
        _locationError = null;
      });
    }
  }

  // ── Worker picker ─────────────────────────────────────────────────────────────
  Future<void> _openWorkerPicker() async {
    final hostId = FirebaseAuth.instance.currentUser?.uid;
    if (hostId == null) return;
    final result = await showModalBottomSheet<List<_WorkerEntry>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkerPickerSheet(
        hostId: hostId,
        initiallySelected: _selectedWorkers,
      ),
    );
    if (result != null) {
      setState(() => _selectedWorkers = result);
      _fetchWorkerSkills();
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedWorkers.isEmpty) {
      _showSnack('Please select at least one gig worker.');
      return;
    }
    if (_workerSkillsXP.isEmpty && _selectedWorkers.length > 1) {
      _showSnack(
        'The selected workers have no skill in common. Pick workers who share at least one skill, or offer them separately.',
        isError: true,
      );
      return;
    }
    if (_selectedSkill == null || _selectedSkill!.isEmpty) {
      _showSnack('Please select a required skill.');
      return;
    }

    final hasLocation = _useMapLocation
        ? _mapPosition != null
        : _gpsPosition != null;
    if (!hasLocation) {
      _showSnack('Location is required. Please enable GPS or select on map.');
      return;
    }

    if (_scheduledDate == null) {
      _showSnack('Schedule is required. Please pick a date and time.', isError: true);
      return;
    }

    if (_scheduledDate != null) {
      final t = _scheduledTime ?? const TimeOfDay(hour: 8, minute: 0);
      final scheduledCheck = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        t.hour,
        t.minute,
      );
      if (scheduledCheck.isBefore(DateTime.now())) {
        _showSnack(
          'Schedule invalid — the date and time you picked have already passed. Please choose a time in the future.',
          isError: true,
        );
        return;
      }
    }

    // Fallback if gig-location geocoding fails during submit.
    final fallbackCurrency = context.read<CurrentUserProvider>().currencyCode;

    setState(() => _posting = true);
    try {
      if (_useMapLocation && _mapPosition != null && _gpsPosition != null) {
        final outside = await isDifferentCountry(
          lat: _mapPosition!.latitude,
          lng: _mapPosition!.longitude,
          otherLat: _gpsPosition!.latitude,
          otherLng: _gpsPosition!.longitude,
        );
        if (outside) {
          if (!mounted) return;
          setState(() => _posting = false);
          _showCountryMismatchDialog();
          return;
        }
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;

      final GeoPoint geoPoint = _useMapLocation && _mapPosition != null
          ? GeoPoint(_mapPosition!.latitude, _mapPosition!.longitude)
          : GeoPoint(_gpsPosition!.latitude, _gpsPosition!.longitude);

      final gigCountry = await countryCodeFromCoordinates(geoPoint.latitude, geoPoint.longitude);
      final currency = gigCountry != null
          ? CurrencyFormatter.countryToCurrency(gigCountry)
          : fallbackCurrency;

      DateTime? scheduledAt;
      if (_scheduledDate != null) {
        final t = _scheduledTime ?? const TimeOfDay(hour: 8, minute: 0);
        scheduledAt = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          t.hour,
          t.minute,
        );
      }

      final rate = double.parse(_budgetCtrl.text.trim());
      final isSingle = _selectedWorkers.length == 1;
      final gig = OfferedGigModel(
        hostId: uid,
        hostName: widget.hostName,
        // Legacy single-recipient shape stays exactly as before — the
        // subcollection is only used once there's genuinely more than one
        // recipient to track independently.
        workerId: isSingle ? _selectedWorkers.single.uid : null,
        workerName: isSingle ? _selectedWorkers.single.name : null,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        skillRequired: _selectedSkill!,
        experienceLevel: _experienceLevel,
        budget: rate,
        currencyCode: currency,
        location: geoPoint,
        address: _address,
        scheduledDate: scheduledAt,
        workerSlots: _selectedWorkers.length,
        ratePerSlot: rate,
      );

      final gigRef = await FirebaseFirestore.instance
          .collection('offered_gigs')
          .add(gig.toMap());

      if (!isSingle) {
        final batch = FirebaseFirestore.instance.batch();
        for (final worker in _selectedWorkers) {
          batch.set(
            gigRef.collection('workers').doc(worker.uid),
            WorkerSlotModel(
              workerId: worker.uid,
              workerName: worker.name,
              gigId: gigRef.id,
              gigCollection: 'offered_gigs',
              hostId: uid,
              hostName: widget.hostName,
              rate: rate,
              currencyCode: currency,
              status: 'offered',
            ).toMap()
              ..['offeredAt'] = FieldValue.serverTimestamp(),
          );
        }
        await batch.commit();
      }

      if (!mounted) return;
      setState(() => _posting = false);
      _showSuccessSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _showSnack('Failed to post gig. Please try again.');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: isError ? const TextStyle(color: Colors.white) : null,
        ),
        backgroundColor: isError ? Colors.redAccent : Theme.of(context).cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showCountryMismatchDialog() {
    _errorPlayer.play(AssetSource('sounds/error-sound.mp3'));
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
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.public_off_rounded,
                color: Colors.red,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Location Outside Your Country',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You can only post gigs within your own country. Please pick a location closer to you.',
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

  void _showSuccessSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(
        onDone: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _saveAsTemplate() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showSnack('Enter a title before saving as template.');
      return;
    }
    final budgetVal = double.tryParse(_budgetCtrl.text.trim()) ?? 0;
    if (budgetVal <= 0) {
      _showSnack('Enter a valid amount before saving as template.');
      return;
    }
    // Capture before async gap.
    final currency = context.read<CurrentUserProvider>().currencyCode;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TemplateNameDialog(initialName: title),
    );
    if (name == null || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('gig_templates')
          .add(
            GigTemplateModel(
              hostId: uid,
              gigType: 'offered',
              name: name.isNotEmpty ? name : title,
              title: title,
              description: _descCtrl.text.trim(),
              budget: budgetVal,
              currencyCode: currency,
              skillRequired: _selectedSkill ?? '',
              experienceLevel: _experienceLevel,
              createdAt: DateTime.now(),
            ).toMap(),
          );
      if (mounted) _showSnack('Template saved!');
    } catch (_) {
      if (mounted) _showSnack('Failed to save template.');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: kSub,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: _kPurple, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'Post Offered Gig',
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Gig Worker ────────────────────────────────────
                _SectionLabel('Gig Worker'),
                const SizedBox(height: 6),
                const Text(
                  'Select the worker you want to offer this gig to',
                  style: TextStyle(color: kSub, fontSize: 12),
                ),
                const SizedBox(height: 10),
                _buildWorkerField(),
                const SizedBox(height: 20),

                // ── Title ─────────────────────────────────────────
                _SectionLabel('Title'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _titleCtrl,
                  hint: 'e.g. Fix the plumbing in my bathroom',
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Title is required'
                      : null,
                ),
                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────
                _SectionLabel('Description'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _descCtrl,
                  hint:
                      'Describe the task, expectations, and any special notes...',
                  maxLines: 4,
                ),
                const SizedBox(height: 20),

                // ── Skill Required ────────────────────────────────
                _SectionLabel('Skill Required'),
                const SizedBox(height: 10),
                _buildSkillDropdown(),
                const SizedBox(height: 20),

                // ── Experience Level ──────────────────────────────
                _SectionLabel('Experience Level'),
                const SizedBox(height: 10),
                _buildExperienceDropdown(),
                const SizedBox(height: 20),

                // ── Amount ────────────────────────────────────────
                _SectionLabel('Amount'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _budgetCtrl,
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Enter a valid amount';
                    return null;
                  },
                  prefix: Text(
                    '${CurrencyFormatter.symbol(context.read<CurrentUserProvider>().currencyCode)} ',
                    style: const TextStyle(
                      color: _kPurple,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Schedule ──────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'Schedule',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildScheduleRow(),
                const SizedBox(height: 20),

                // ── Location ──────────────────────────────────────
                _SectionLabel('Location'),
                const SizedBox(height: 10),
                _buildLocationSection(),
                const SizedBox(height: 36),

                // ── Post Button ───────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _posting ? null : _submit,
                    icon: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _posting ? 'Sending Offer...' : 'Send Offered Gig',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kPurple.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Save as Template ──────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _posting ? null : _saveAsTemplate,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text(
                      'Save as Template',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPurple,
                      side: BorderSide(color: _kPurple.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Worker Field ──────────────────────────────────────────────────────────────
  Widget _buildWorkerField() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasWorker = _selectedWorkers.isNotEmpty;
    final isSingle = _selectedWorkers.length == 1;

    return GestureDetector(
      onTap: _openWorkerPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasWorker ? _kPurple.withValues(alpha: 0.6) : borderColor,
            width: hasWorker ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hasWorker
                    ? _kPurple.withValues(alpha: 0.12)
                    : kSub.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasWorker ? Icons.groups_rounded : Icons.person_search_rounded,
                color: hasWorker ? _kPurple : kSub,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: !hasWorker
                  ? const Text(
                      'Search by name or ID...',
                      style: TextStyle(color: kSub, fontSize: 14),
                    )
                  : isSingle
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedWorkers.single.name,
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedWorkers.single.email,
                              style: const TextStyle(color: kSub, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedWorkers.length} workers selected',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _selectedWorkers
                                  .map(
                                    (w) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kPurple.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            w.name,
                                            style: const TextStyle(
                                              color: _kPurple,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => setState(() {
                                              _selectedWorkers = _selectedWorkers
                                                  .where((e) => e.uid != w.uid)
                                                  .toList();
                                              _fetchWorkerSkills();
                                            }),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 12,
                                              color: _kPurple,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
            ),
            Icon(
              hasWorker
                  ? Icons.swap_horiz_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: kSub,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Fetch skills common to ALL selected workers ──────────────────────────
  // The required skill has to be one every offered worker actually has, so
  // with multiple workers selected this is the intersection of their
  // skillsXP keys rather than one worker's full skill set.
  Future<void> _fetchWorkerSkills() async {
    if (_selectedWorkers.isEmpty) {
      setState(() {
        _selectedSkill = null;
        _workerSkillsXP = {};
      });
      return;
    }
    setState(() {
      _loadingWorkerSkills = true;
      _selectedSkill = null;
      _workerSkillsXP = {};
    });
    try {
      final docs = await Future.wait(
        _selectedWorkers.map(
          (w) => FirebaseFirestore.instance.collection('users').doc(w.uid).get(),
        ),
      );
      if (!mounted) return;
      final perWorkerSkills = docs.map((doc) {
        final raw = doc.data()?['skillsXP'] as Map<String, dynamic>? ?? {};
        return raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
      }).toList();

      Map<String, int> common = perWorkerSkills.isNotEmpty
          ? Map<String, int>.from(perWorkerSkills.first)
          : {};
      for (final skills in perWorkerSkills.skip(1)) {
        common.removeWhere((key, _) => !skills.containsKey(key));
      }

      setState(() {
        _workerSkillsXP = common;
        _loadingWorkerSkills = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWorkerSkills = false);
    }
  }

  // ── Skill Picker ──────────────────────────────────────────────────────────
  Widget _buildSkillDropdown() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final workerSkills = _workerSkillsXP.keys.toList()..sort();
    final noWorker = _selectedWorkers.isEmpty;
    final enabled =
        !noWorker && !_loadingWorkerSkills && workerSkills.isNotEmpty;

    String hintText;
    if (noWorker) {
      hintText = 'Select a worker first...';
    } else if (_loadingWorkerSkills) {
      hintText = 'Loading worker skills...';
    } else if (workerSkills.isEmpty) {
      hintText = _selectedWorkers.length > 1
          ? 'Workers have no skill in common'
          : 'Worker has no skills yet';
    } else {
      hintText = 'Select a skill...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: enabled ? cardColor : cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedSkill != null
              ? _kPurple.withValues(alpha: 0.6)
              : borderColor,
          width: _selectedSkill != null ? 1.5 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSkill,
          isExpanded: true,
          dropdownColor: cardColor,
          hint: Text(
            hintText,
            style: const TextStyle(color: kSub, fontSize: 14),
          ),
          icon: _loadingWorkerSkills
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: kSub, strokeWidth: 2),
                )
              : const Icon(Icons.keyboard_arrow_down_rounded, color: kSub),
          style: TextStyle(color: onSurface, fontSize: 14),
          items: enabled
              ? workerSkills
                    .map(
                      (skill) => DropdownMenuItem(
                        value: skill,
                        child: Text(
                          skill,
                          style: TextStyle(color: onSurface, fontSize: 14),
                        ),
                      ),
                    )
                    .toList()
              : null,
          onChanged: enabled ? (v) => setState(() => _selectedSkill = v) : null,
        ),
      ),
    );
  }

  // ── Experience Dropdown ───────────────────────────────────────────────────────
  Widget _buildExperienceDropdown() {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPurple.withValues(alpha: 0.6), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _experienceLevel,
          isExpanded: true,
          dropdownColor: cardColor,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kSub),
          style: TextStyle(color: onSurface, fontSize: 14),
          items: _kLevels.map((level) {
            final lvValue = level.$1;
            final lvLabel = level.$2;
            final lvSub = level.$3;
            return DropdownMenuItem<String>(
              value: lvValue,
              child: Row(
                children: [
                  Text(
                    lvLabel,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '• $lvSub',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) => setState(() => _experienceLevel = v!),
        ),
      ),
    );
  }

  // ── Schedule Row ──────────────────────────────────────────────────────────────
  Widget _buildScheduleRow() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dateSet = _scheduledDate != null;
    final timeSet = _scheduledTime != null;
    final dateLabel = dateSet
        ? DateFormat('EEE, MMM d').format(_scheduledDate!)
        : 'Pick a date';
    final timeLabel = timeSet ? _scheduledTime!.format(context) : 'Pick a time';

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickDate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: dateSet ? _kPurple.withValues(alpha: 0.08) : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: dateSet
                      ? _kPurple.withValues(alpha: 0.6)
                      : borderColor,
                  width: dateSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: dateSet ? _kPurple : kSub,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: TextStyle(
                        color: dateSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight: dateSet
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dateSet)
                    GestureDetector(
                      onTap: () => setState(() => _scheduledDate = null),
                      child: const Icon(
                        Icons.close_rounded,
                        color: kSub,
                        size: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _pickTime,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: timeSet ? _kPurple.withValues(alpha: 0.08) : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: timeSet
                      ? _kPurple.withValues(alpha: 0.6)
                      : borderColor,
                  width: timeSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    color: timeSet ? _kPurple : kSub,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      timeLabel,
                      style: TextStyle(
                        color: timeSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight: timeSet
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (timeSet)
                    GestureDetector(
                      onTap: () => setState(() => _scheduledTime = null),
                      child: const Icon(
                        Icons.close_rounded,
                        color: kSub,
                        size: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Location Section ──────────────────────────────────────────────────────────
  Widget _buildLocationSection() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasError = !_useMapLocation && _locationError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      (_useMapLocation
                              ? _kPurple
                              : (hasError ? Colors.redAccent : _kPurple))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _useMapLocation
                      ? Icons.map_outlined
                      : (hasError
                            ? Icons.location_off_outlined
                            : Icons.location_on_rounded),
                  color: _useMapLocation
                      ? _kPurple
                      : (hasError ? Colors.redAccent : _kPurple),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _loadingLocation
                    ? const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: _kPurple,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Detecting location...',
                            style: TextStyle(color: kSub, fontSize: 13),
                          ),
                        ],
                      )
                    : hasError
                    ? Text(
                        _locationError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _address.isNotEmpty ? _address : 'Location ready',
                            style: TextStyle(color: onSurface, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _useMapLocation
                                ? 'Map-selected location'
                                : 'Current GPS location',
                            style: TextStyle(
                              color: _useMapLocation ? _kPurple : kSub,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _LocationModeButton(
                icon: Icons.my_location_rounded,
                label: 'Use My Location',
                active: !_useMapLocation,
                accentColor: _kPurple,
                onTap: () {
                  setState(() {
                    _useMapLocation = false;
                    if (_gpsPosition != null && _gpsAddress.isNotEmpty) {
                      _address = _gpsAddress;
                    }
                  });
                  if (_gpsPosition == null) _fetchGpsLocation();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LocationModeButton(
                icon: Icons.map_outlined,
                label: 'Select on Map',
                active: _useMapLocation,
                accentColor: _kPurple,
                onTap: _openMapPicker,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Text Field Builder ────────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? prefix,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: textColor.withValues(alpha: 0.35),
          fontSize: 14,
        ),
        prefix: prefix,
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Picker Bottom Sheet
//  Shows only the host's favorite workers. Allows direct UID lookup for
//  workers not in the favorites list. Host cannot select themselves.
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerPickerSheet extends StatefulWidget {
  final String hostId;
  final List<_WorkerEntry> initiallySelected;
  const _WorkerPickerSheet({required this.hostId, this.initiallySelected = const []});

  @override
  State<_WorkerPickerSheet> createState() => _WorkerPickerSheetState();
}

class _WorkerPickerSheetState extends State<_WorkerPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_WorkerEntry> _favorites = [];
  List<_WorkerEntry> _filtered = [];
  _WorkerEntry? _uidResult;
  bool _loading = true;
  bool _uidSearching = false;
  Timer? _debounce;
  late final Map<String, _WorkerEntry> _selected = {
    for (final w in widget.initiallySelected) w.uid: w,
  };

  void _toggle(_WorkerEntry w) {
    setState(() {
      if (_selected.containsKey(w.uid)) {
        _selected.remove(w.uid);
      } else {
        _selected[w.uid] = w;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final db = FirebaseFirestore.instance;
      final hostDoc = await db.collection('users').doc(widget.hostId).get();
      final ids =
          (hostDoc.data()?['favoriteWorkerIds'] as List?)
              ?.map((e) => e.toString())
              .where((id) => id != widget.hostId)
              .toList() ??
          [];

      if (ids.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final docs = await Future.wait(
        ids.map((id) => db.collection('users').doc(id).get()),
      );

      final workers = await Future.wait(
        docs.where((d) => d.exists).map((d) async {
          final data = d.data() as Map<String, dynamic>;
          final completed = await _fetchCompletedGigsCount(d.id);
          return _WorkerEntry(
            uid: d.id,
            userId: data['userId'] ?? '',
            name: data['name'] ?? 'Unknown',
            email: data['email'] ?? '',
            rating: (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0,
            ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
            completedGigs: completed,
          );
        }),
      );

      if (!mounted) return;
      setState(() {
        _favorites = workers;
        _filtered = workers;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final q = _searchCtrl.text.trim();

    if (q.isEmpty) {
      setState(() {
        _filtered = _favorites;
        _uidResult = null;
        _uidSearching = false;
      });
      return;
    }

    final lower = q.toLowerCase();
    final matched = _favorites
        .where(
          (w) =>
              w.name.toLowerCase().contains(lower) ||
              w.email.toLowerCase().contains(lower) ||
              w.userId.toLowerCase().contains(lower),
        )
        .toList();

    setState(() {
      _filtered = matched;
      if (matched.isNotEmpty) {
        _uidResult = null;
        _uidSearching = false;
      }
    });

    // When no favorites match, try a direct UID lookup after a short delay
    if (matched.isEmpty) {
      setState(() => _uidSearching = true);
      _debounce = Timer(
        const Duration(milliseconds: 600),
        () => _lookupByUserId(q),
      );
    }
  }

  // Queries the users collection by the custom `userId` field (e.g. "YSJ135610").
  // Only fires when the query matches the expected format [A-Z]{3}[0-9]{6}.
  Future<void> _lookupByUserId(String query) async {
    if (!mounted) {
      setState(() => _uidSearching = false);
      return;
    }

    final normalised = query.trim().toUpperCase();
    final validFormat = RegExp(r'^[A-Z]{3}[0-9]{6}$').hasMatch(normalised);
    if (!validFormat) {
      setState(() {
        _uidResult = null;
        _uidSearching = false;
      });
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: normalised)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        setState(() {
          _uidResult = null;
          _uidSearching = false;
        });
        return;
      }
      final doc = snap.docs.first;
      // Block self-selection
      if (doc.id == widget.hostId) {
        setState(() {
          _uidResult = null;
          _uidSearching = false;
        });
        return;
      }
      final data = doc.data();
      final completed = await _fetchCompletedGigsCount(doc.id);
      if (!mounted) return;
      setState(() {
        _uidResult = _WorkerEntry(
          uid: doc.id,
          userId: data['userId'] ?? normalised,
          name: data['name'] ?? 'Unknown',
          email: data['email'] ?? '',
          rating: (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0,
          ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
          completedGigs: completed,
        );
        _uidSearching = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _uidResult = null;
          _uidSearching = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;
    const purple = _kPurple;

    final hasQuery = _searchCtrl.text.trim().isNotEmpty;
    final showEmpty =
        !_loading && _filtered.isEmpty && _uidResult == null && !_uidSearching;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kSub.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Gig Worker',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'From your favorites · or search by worker ID',
                      style: TextStyle(color: kSub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_rounded, color: purple, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _loading ? '...' : '${_favorites.length}',
                      style: const TextStyle(
                        color: purple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            style: TextStyle(color: onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by worker ID...',
              hintStyle: TextStyle(
                color: onSurface.withValues(alpha: 0.35),
                fontSize: 14,
              ),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: kSub,
                size: 20,
              ),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: kSub,
                        size: 18,
                      ),
                      onPressed: () => _searchCtrl.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: purple, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: purple))
                : showEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasQuery
                              ? Icons.person_off_outlined
                              : Icons.favorite_border_rounded,
                          color: kSub.withValues(alpha: 0.5),
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasQuery
                              ? 'No worker found'
                              : 'No favorite workers yet',
                          style: const TextStyle(
                            color: kSub,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasQuery
                              ? 'Check the worker ID and try again'
                              : 'Add workers to favorites from your gig history',
                          style: const TextStyle(color: kSub, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (_filtered.isNotEmpty) ...[
                        if (!hasQuery)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Favorite Workers',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ..._filtered.map(
                          (w) => _WorkerTile(
                            worker: w,
                            onTap: () => _toggle(w),
                            borderColor: borderColor,
                            isFavorite: true,
                            selected: _selected.containsKey(w.uid),
                          ),
                        ),
                      ],
                      if (_uidSearching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: purple,
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Looking up worker ID...',
                                  style: TextStyle(color: kSub, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_uidResult != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                color: kSub,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Found by worker ID',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _WorkerTile(
                          worker: _uidResult!,
                          onTap: () => _toggle(_uidResult!),
                          borderColor: borderColor,
                          isFavorite: false,
                          selected: _selected.containsKey(_uidResult!.uid),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected.values.toList()),
              style: ElevatedButton.styleFrom(
                backgroundColor: purple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: purple.withValues(alpha: 0.35),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _selected.isEmpty
                    ? 'Select workers'
                    : 'Use ${_selected.length} selected worker${_selected.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable worker list tile
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerTile extends StatelessWidget {
  final _WorkerEntry worker;
  final VoidCallback onTap;
  final Color borderColor;
  final bool isFavorite;
  final bool selected;

  const _WorkerTile({
    required this.worker,
    required this.onTap,
    required this.borderColor,
    required this.isFavorite,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const purple = _kPurple;

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: purple, size: 20),
          ),
          title: Text(
            worker.name,
            style: TextStyle(
              color: onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    worker.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: kSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ' (${worker.ratingCount})',
                    style: const TextStyle(color: kSub, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${worker.completedGigs} completed',
                    style: const TextStyle(color: kSub, fontSize: 11),
                  ),
                ],
              ),
              if (worker.email.isNotEmpty)
                Text(
                  worker.email,
                  style: const TextStyle(color: kSub, fontSize: 11),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFavorite)
                const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFEC4899),
                  size: 14,
                ),
              const SizedBox(width: 4),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? _kPurple : kSub,
                size: 20,
              ),
            ],
          ),
        ),
        Divider(color: borderColor, height: 1),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Label
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Location Mode Button
// ─────────────────────────────────────────────────────────────────────────────
class _LocationModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  const _LocationModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: 0.1)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.6)
                : Theme.of(context).dividerColor,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? accentColor : kSub, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? accentColor : kSub,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Map Picker
// ─────────────────────────────────────────────────────────────────────────────
class _SavedLocation {
  final LatLng position;
  final String address;
  const _SavedLocation({required this.position, required this.address});
}

class _PickedLocation {
  final LatLng position;
  final String address;
  const _PickedLocation({required this.position, required this.address});
}

class _MapPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  const _MapPickerScreen({this.initialPosition});

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  GoogleMapController? _googleMapController;
  bool _useGoogleMaps = true;
  final _osmController = fm.MapController();
  bool _osmMapReady = false;
  final _searchCtrl = TextEditingController();
  late LatLng _picked;
  String _address = '';
  bool _geocoding = false;
  bool _searching = false;
  String? _searchError;
  LatLng? _myLocation;
  int _geocodeRequestId = 0;
  Timer? _debounce;
  Timer? _searchDebounce;
  // Skips the geocode that would otherwise fire immediately after the
  // explicit initState() lookup, or after a search/recenter jump that
  // already has (or doesn't need) its own address.
  bool _suppressNextGeocode = false;
  List<Map<String, dynamic>> _placeSuggestions = [];
  bool _showSuggestions = false;
  _SavedLocation? _recentLocation;
  _SavedLocation? _favoriteLocation;
  bool _showQuickPicks = false;
  bool _locationLocked = false;
  final _searchFocusNode = FocusNode();

  static final _defaultCenter = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPosition ?? _defaultCenter;
    _geocodePosition(_picked);
    GmsAvailability.isAvailable.then((v) {
      if (mounted) setState(() => _useGoogleMaps = v);
    });
    _loadSavedLocations();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _debounce?.cancel();
    _googleMapController?.dispose();
    _osmController.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _recenterToMyLocation() async {
    if (_myLocation != null) {
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_myLocation!, 14.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(
          ll.LatLng(_myLocation!.latitude, _myLocation!.longitude),
          14.0,
        );
      }
      return;
    }
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_myLocation!, 14.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(
          ll.LatLng(_myLocation!.latitude, _myLocation!.longitude),
          14.0,
        );
      }
    } catch (_) {}
  }

  // Builds a clean short address from a Nominatim result, preferring the
  // specific place name over the raw display_name blob. Returns '' if the
  // result carries no usable naming at all.
  String _formatNominatimResult(Map<String, dynamic> data) {
    final addrObj = data['address'] as Map<String, dynamic>?;
    final placeName = data['name'] as String?;
    final displayName = data['display_name'] as String?;
    String? roadPart;
    if (addrObj != null) {
      final houseNumber = addrObj['house_number'] as String?;
      final road =
          (addrObj['road'] ?? addrObj['pedestrian'] ?? addrObj['footway'])
              as String?;
      if (houseNumber != null &&
          houseNumber.isNotEmpty &&
          road != null &&
          road.isNotEmpty) {
        roadPart = '$houseNumber $road';
      } else if (road != null && road.isNotEmpty) {
        roadPart = road;
      }
    }
    final parts = [
      if (placeName != null && placeName.isNotEmpty) placeName,
      roadPart,
      if (addrObj != null) ...[
        addrObj['suburb'] ?? addrObj['neighbourhood'],
        addrObj['city'] ?? addrObj['town'] ?? addrObj['village'],
        addrObj['state'],
      ],
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return '';
  }

  // Returns a specificity score for a Nominatim result — higher means more
  // specific. Used to pick the best result when multiple candidates are returned.
  int _nominatimSpecificity(Map<String, dynamic> result) {
    final addr = result['address'] as Map<String, dynamic>? ?? {};
    if (addr.containsKey('house_number')) return 5;
    final cls = result['class'] as String? ?? '';
    if (cls == 'building') return 4;
    if (addr.containsKey('road') ||
        addr.containsKey('pedestrian') ||
        addr.containsKey('footway'))
      return 3;
    if (addr.containsKey('suburb') || addr.containsKey('neighbourhood'))
      return 2;
    if (addr.containsKey('city') ||
        addr.containsKey('town') ||
        addr.containsKey('village'))
      return 1;
    return 0;
  }

  Future<void> _fetchSuggestions(String input) async {
    // if (kIsWeb) { return; } // Places API blocked by CORS on web
    if (input.trim().length < 2) {
      if (_showSuggestions) {
        setState(() {
          _placeSuggestions = [];
          _showSuggestions = false;
        });
      }
      return;
    }
    final bias = _myLocation ?? _picked;
    final uri =
        Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        ).replace(
          queryParameters: {
            'input': input.trim(),
            'key': kGoogleMapsApiKey,
            'components': 'country:ph',
            'location': '${bias.latitude},${bias.longitude}',
            'radius': '50000',
            'language': 'en',
          },
        );
    try {
      final res = await http.get(uri);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        debugPrint(
          '[Places] status=$status msg=${data['error_message'] ?? ''}',
        );
        return;
      }
      final predictions = (data['predictions'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      setState(() {
        _placeSuggestions = predictions;
        _showSuggestions = predictions.isNotEmpty;
      });
    } catch (e) {
      debugPrint('[Places] network error: $e');
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> prediction) async {
    final placeId = prediction['place_id'] as String;
    final description = prediction['description'] as String;
    _searchCtrl.text = description;
    setState(() {
      _placeSuggestions = [];
      _showSuggestions = false;
      _searching = true;
      _searchError = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final uri =
          Uri.parse(
            'https://maps.googleapis.com/maps/api/place/details/json',
          ).replace(
            queryParameters: {
              'place_id': placeId,
              'fields': 'name,formatted_address,geometry',
              'key': kGoogleMapsApiKey,
              'language': 'en',
            },
          );
      final res = await http.get(uri);
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      if (result == null) {
        setState(() {
          _searchError = 'Could not get location details. Try again.';
          _searching = false;
        });
        return;
      }
      final loc = ((result['geometry'] as Map)['location']) as Map;
      final point = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
      final formattedAddress =
          result['formatted_address'] as String? ?? description;
      _suppressNextGeocode = true;
      setState(() {
        _picked = point;
        _address = formattedAddress;
        _searching = false;
        _locationLocked = true;
      });
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(point, 18.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(ll.LatLng(point.latitude, point.longitude), 18.0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Could not find location. Try again.';
        _searching = false;
      });
    }
  }

  Future<void> _searchAddress() async {
    // Prefer an already-fetched autocomplete result over a fresh geocode.
    if (_placeSuggestions.isNotEmpty) {
      await _selectSuggestion(_placeSuggestions.first);
      return;
    }
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(
            queryParameters: {
              'q': query,
              'format': 'json',
              'limit': '5',
              'addressdetails': '1',
            },
          );
      final res = await http.get(
        uri,
        headers: {'User-Agent': 'giggre_app/1.0'},
      );
      if (!mounted) return;
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) {
        setState(() {
          _searchError = 'No results found. Try a different address.';
          _searching = false;
        });
        return;
      }
      // Pick the most specific result (specific address > road > neighbourhood > city).
      final sorted =
          List<Map<String, dynamic>>.from(data.cast<Map<String, dynamic>>())
            ..sort(
              (a, b) =>
                  _nominatimSpecificity(b).compareTo(_nominatimSpecificity(a)),
            );
      final result = sorted.first;
      final lat = double.parse(result['lat'] as String);
      final lon = double.parse(result['lon'] as String);
      final point = LatLng(lat, lon);
      // The search result already carries a reliable address — use it
      // directly instead of depending on a second reverse-geocode call
      // that can independently fail and mask a perfectly good result.
      final formatted = _formatNominatimResult(result);
      _suppressNextGeocode = true;
      setState(() {
        _picked = point;
        _address = formatted.isNotEmpty ? formatted : query;
        _searching = false;
        _locationLocked = true;
      });
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(point, 18.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(ll.LatLng(point.latitude, point.longitude), 18.0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Could not find location. Try again.';
        _searching = false;
      });
    }
  }

  Future<void> _geocodePosition(LatLng pos) async {
    if (!mounted) return;
    final requestId = ++_geocodeRequestId;
    setState(() => _geocoding = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${pos.latitude}&lon=${pos.longitude}&format=json&zoom=18&addressdetails=1',
      );
      final res = await http.get(
        uri,
        headers: {'User-Agent': 'giggre_app/1.0'},
      );
      if (!mounted || requestId != _geocodeRequestId) return;
      String address = 'Selected location';
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final formatted = _formatNominatimResult(data);
        if (formatted.isNotEmpty) address = formatted;
      }
      if (requestId != _geocodeRequestId) return;
      setState(() {
        _address = address;
        _geocoding = false;
      });
    } catch (e) {
      if (!mounted || requestId != _geocodeRequestId) return;
      setState(() {
        _address = 'Could not get address';
        _geocoding = false;
      });
    }
  }

  // ── Saved locations ──────────────────────────────────────────────────────────
  Future<void> _loadSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentLat = prefs.getDouble('map_picker_recent_lat');
    final recentLng = prefs.getDouble('map_picker_recent_lng');
    final recentAddr = prefs.getString('map_picker_recent_address');
    final favLat = prefs.getDouble('map_picker_fav_lat');
    final favLng = prefs.getDouble('map_picker_fav_lng');
    final favAddr = prefs.getString('map_picker_fav_address');
    if (!mounted) return;
    setState(() {
      if (recentLat != null && recentLng != null && recentAddr != null) {
        _recentLocation = _SavedLocation(
          position: LatLng(recentLat, recentLng),
          address: recentAddr,
        );
      }
      if (favLat != null && favLng != null && favAddr != null) {
        _favoriteLocation = _SavedLocation(
          position: LatLng(favLat, favLng),
          address: favAddr,
        );
      }
    });
  }

  Future<void> _saveRecentLocation() async {
    if (_address.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('map_picker_recent_lat', _picked.latitude);
    await prefs.setDouble('map_picker_recent_lng', _picked.longitude);
    await prefs.setString('map_picker_recent_address', _address);
  }

  Future<void> _saveFavoriteLocation() async {
    if (_address.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('map_picker_fav_lat', _picked.latitude);
    await prefs.setDouble('map_picker_fav_lng', _picked.longitude);
    await prefs.setString('map_picker_fav_address', _address);
    if (!mounted) return;
    setState(
      () => _favoriteLocation = _SavedLocation(
        position: _picked,
        address: _address,
      ),
    );
  }

  Future<void> _clearFavoriteLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('map_picker_fav_lat');
    await prefs.remove('map_picker_fav_lng');
    await prefs.remove('map_picker_fav_address');
    if (!mounted) return;
    setState(() => _favoriteLocation = null);
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    if (_searchFocusNode.hasFocus && _searchCtrl.text.isEmpty) {
      setState(() => _showQuickPicks = true);
    } else if (!_searchFocusNode.hasFocus) {
      setState(() => _showQuickPicks = false);
    }
  }

  void _selectQuickPick(_SavedLocation loc) {
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    _suppressNextGeocode = true;
    setState(() {
      _picked = loc.position;
      _address = loc.address;
      _showQuickPicks = false;
      _searchError = null;
      _placeSuggestions = [];
      _showSuggestions = false;
      _locationLocked = true;
    });
    if (_useGoogleMaps) {
      _googleMapController?.animateCamera(
        CameraUpdate.newLatLngZoom(loc.position, 18.0),
      );
    } else if (_osmMapReady) {
      _osmController.move(
        ll.LatLng(loc.position.latitude, loc.position.longitude),
        18.0,
      );
    }
  }

  bool _isFavoriteCurrentLocation() {
    if (_favoriteLocation == null) return false;
    const eps = 0.00001;
    return (_favoriteLocation!.position.latitude - _picked.latitude).abs() <
            eps &&
        (_favoriteLocation!.position.longitude - _picked.longitude).abs() < eps;
  }

  // Called continuously while the map is being dragged — the pin is fixed
  // at screen-center, so whatever's under it is always the current pick.
  void _onCameraMoved(LatLng center) {
    if (_locationLocked) return;
    setState(() {
      _picked = center;
      _showQuickPicks = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_suppressNextGeocode) {
        _suppressNextGeocode = false;
        return;
      }
      _geocodePosition(_picked);
    });
  }

  // Google Maps reports when the camera has settled — resolve immediately
  // instead of waiting out the debounce window.
  void _onCameraIdle() {
    if (_locationLocked) return;
    _debounce?.cancel();
    if (_suppressNextGeocode) {
      _suppressNextGeocode = false;
      return;
    }
    _geocodePosition(_picked);
  }

  Widget _buildQuickPicksList() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasFav = _favoriteLocation != null;
    final hasRecent = _recentLocation != null;

    Widget tile({
      required IconData icon,
      required Color iconColor,
      required String label,
      required String address,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      address,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasFav)
              tile(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF59E0B),
                label: 'Default Location',
                address: _favoriteLocation!.address,
                onTap: () => _selectQuickPick(_favoriteLocation!),
              ),
            if (hasFav && hasRecent) Divider(height: 1, color: borderColor),
            if (hasRecent)
              tile(
                icon: Icons.history_rounded,
                iconColor: kSub,
                label: 'Recent',
                address: _recentLocation!.address,
                onTap: () => _selectQuickPick(_recentLocation!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOsmMap() {
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: ll.LatLng(_picked.latitude, _picked.longitude),
        initialZoom: 16.0,
        onMapReady: () {
          if (mounted) setState(() => _osmMapReady = true);
        },
        onPositionChanged: (camera, hasGesture) {
          if (!hasGesture) return;
          _onCameraMoved(
            LatLng(camera.center.latitude, camera.center.longitude),
          );
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.mobile',
        ),
        if (_locationLocked)
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: ll.LatLng(_picked.latitude, _picked.longitude),
                width: 44,
                height: 44,
                alignment: Alignment.bottomCenter,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 44,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _confirm() {
    _saveRecentLocation();
    Navigator.pop(
      context,
      _PickedLocation(
        position: _picked,
        address: _address.isNotEmpty ? _address : 'Selected location',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    const purple = _kPurple;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: kSub,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Location',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: Stack(
        children: [
          _useGoogleMaps
              ? GoogleMap(
                  style: Theme.of(context).brightness == Brightness.dark
                      ? kDarkMapStyle
                      : null,
                  onMapCreated: (controller) =>
                      _googleMapController = controller,
                  initialCameraPosition: CameraPosition(
                    target: _picked,
                    zoom: 16.0,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onCameraMove: (position) => _onCameraMoved(position.target),
                  onCameraIdle: _onCameraIdle,
                  markers: _locationLocked
                      ? {
                          Marker(
                            markerId: const MarkerId('selected'),
                            position: _picked,
                          ),
                        }
                      : {},
                )
              : _buildOsmMap(),

          // ── Fixed center pin — only shown when location is not locked;
          // once locked a real map marker is used instead. ─────────────
          if (!_locationLocked)
            IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 44,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // ── Search bar ───────────────────────────────────────
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocusNode,
                    onTap: () {
                      if (_searchCtrl.text.isEmpty) {
                        setState(() => _showQuickPicks = true);
                      }
                    },
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      if (value.trim().isEmpty) {
                        setState(() {
                          _placeSuggestions = [];
                          _showSuggestions = false;
                          _showQuickPicks = true;
                        });
                        return;
                      }
                      setState(() => _showQuickPicks = false);
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 350),
                        () => _fetchSuggestions(value),
                      );
                    },
                    onSubmitted: (_) => _searchAddress(),
                    style: TextStyle(color: onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search address or place...',
                      hintStyle: TextStyle(
                        color: onSurface.withValues(alpha: 0.4),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: kSub,
                        size: 20,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: purple,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                color: purple,
                                size: 20,
                              ),
                              onPressed: _searchAddress,
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                if (_showQuickPicks &&
                    (_favoriteLocation != null || _recentLocation != null))
                  _buildQuickPicksList(),
                if (_searchError != null)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_showSuggestions && _placeSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _placeSuggestions.length > 5
                            ? 5
                            : _placeSuggestions.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: borderColor),
                        itemBuilder: (context, index) {
                          final p = _placeSuggestions[index];
                          final mainText =
                              (p['structured_formatting'] as Map?)?['main_text']
                                  as String? ??
                              p['description'] as String? ??
                              '';
                          final secondaryText =
                              (p['structured_formatting']
                                      as Map?)?['secondary_text']
                                  as String?;
                          return InkWell(
                            onTap: () => _selectSuggestion(p),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                    color: kSub,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mainText,
                                          style: TextStyle(
                                            color: onSurface,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (secondaryText != null &&
                                            secondaryText.isNotEmpty)
                                          Text(
                                            secondaryText,
                                            style: TextStyle(
                                              color: onSurface.withValues(
                                                alpha: 0.55,
                                              ),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Recenter button ───────────────────────────────────
          Positioned(
            bottom: 100,
            right: 16,
            child: GestureDetector(
              onTap: _recenterToMyLocation,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cardColor,
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
                  color: _myLocation != null ? const Color(0xFF8B5CF6) : kSub,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: purple,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _geocoding
                            ? const Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: purple,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Getting address...',
                                    style: TextStyle(color: kSub, fontSize: 13),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _address.isNotEmpty
                                        ? _address
                                        : 'Location selected',
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _locationLocked
                                        ? 'Location pinned'
                                        : 'Drag the map to fine-tune the pin',
                                    style: TextStyle(
                                      color: _locationLocked
                                          ? const Color(0xFF10B981)
                                          : kSub,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Lat: ${_picked.latitude.toStringAsFixed(6)}  Lng: ${_picked.longitude.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                      color: kSub,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (!_geocoding) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (_isFavoriteCurrentLocation()) {
                              _clearFavoriteLocation();
                            } else {
                              _saveFavoriteLocation();
                            }
                          },
                          child: Icon(
                            _isFavoriteCurrentLocation()
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: _isFavoriteCurrentLocation()
                                ? const Color(0xFFF59E0B)
                                : kSub,
                            size: 24,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_locationLocked) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _locationLocked = false);
                          if (_useGoogleMaps) {
                            _googleMapController?.animateCamera(
                              CameraUpdate.newLatLng(_picked),
                            );
                          } else if (_osmMapReady) {
                            _osmController.move(
                              ll.LatLng(
                                _picked.latitude,
                                _picked.longitude,
                              ),
                              _osmController.camera.zoom,
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.edit_location_alt_outlined,
                          size: 16,
                        ),
                        label: const Text(
                          'Select Different Location',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: purple,
                          side: BorderSide(
                            color: purple.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _geocoding ? null : _confirm,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: purple.withValues(alpha: 0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Success Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SuccessSheet extends StatelessWidget {
  final VoidCallback onDone;
  const _SuccessSheet({required this.onDone});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: _kPurple.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: const Icon(Icons.send_rounded, color: _kPurple, size: 38),
          ),
          const SizedBox(height: 20),
          Text(
            'Offered Gig Sent!',
            style: TextStyle(
              color: onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your offer has been sent to the worker.\nThey will be notified shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'View My Gigs',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
