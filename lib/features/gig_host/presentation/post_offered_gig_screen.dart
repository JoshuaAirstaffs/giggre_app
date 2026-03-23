import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../models/offered_gig_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Static skill tags
// ─────────────────────────────────────────────────────────────────────────────
const _kSkills = [
  'Plumbing',
  'Electrical Work',
  'Carpentry',
  'Painting',
  'Web Development',
  'Mobile Development',
  'Graphic Design',
  'Accounting',
  'Photography',
  'Videography',
  'Cooking',
  'Tutoring',
  'Translation',
  'Content Writing',
  'Data Entry',
  'HVAC',
  'Welding',
  'Landscaping',
  'IT Support',
  'SEO / Marketing',
];

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
  final String uid;
  final String name;
  final String email;
  const _WorkerEntry({required this.uid, required this.name, required this.email});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Post Offered Gig Screen
// ─────────────────────────────────────────────────────────────────────────────
class PostOfferedGigScreen extends StatefulWidget {
  final String hostName;
  const PostOfferedGigScreen({super.key, required this.hostName});

  @override
  State<PostOfferedGigScreen> createState() => _PostOfferedGigScreenState();
}

class _PostOfferedGigScreenState extends State<PostOfferedGigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  // Worker selection
  _WorkerEntry? _selectedWorker;

  // Skill
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
  bool _loadingLocation = false;
  String? _locationError;
  bool _useMapLocation = false;

  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _fetchGpsLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
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

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      String address = 'Unknown location';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          if (p.street != null && p.street!.isNotEmpty) p.street,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
            p.administrativeArea,
        ];
        address = parts.join(', ');
      }

      if (!mounted) return;
      setState(() {
        _gpsPosition = pos;
        if (!_useMapLocation) _address = address;
        _loadingLocation = false;
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
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: _kPurple,
                onPrimary: Colors.white,
              ),
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
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: _kPurple,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  // ── Map location picker ───────────────────────────────────────────────────────
  Future<void> _openMapPicker() async {
    final initial = _mapPosition ??
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
    final result = await showModalBottomSheet<_WorkerEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkerPickerSheet(
        excludeUid: FirebaseAuth.instance.currentUser?.uid,
      ),
    );
    if (result != null) {
      setState(() => _selectedWorker = result);
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedWorker == null) {
      _showSnack('Please select a gig worker.');
      return;
    }
    if (_selectedSkill == null || _selectedSkill!.isEmpty) {
      _showSnack('Please select a required skill.');
      return;
    }

    final hasLocation = _useMapLocation ? _mapPosition != null : _gpsPosition != null;
    if (!hasLocation) {
      _showSnack('Location is required. Please enable GPS or select on map.');
      return;
    }

    setState(() => _posting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final GeoPoint geoPoint = _useMapLocation && _mapPosition != null
          ? GeoPoint(_mapPosition!.latitude, _mapPosition!.longitude)
          : GeoPoint(_gpsPosition!.latitude, _gpsPosition!.longitude);

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

      final gig = OfferedGigModel(
        hostId: uid,
        hostName: widget.hostName,
        workerId: _selectedWorker!.uid,
        workerName: _selectedWorker!.name,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        skillRequired: _selectedSkill!,
        experienceLevel: _experienceLevel,
        budget: double.parse(_budgetCtrl.text.trim()),
        location: geoPoint,
        address: _address,
        scheduledDate: scheduledAt,
      );

      await FirebaseFirestore.instance.collection('offered_gigs').add(gig.toMap());

      if (!mounted) return;
      setState(() => _posting = false);
      _showSuccessSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _showSnack('Failed to post gig. Please try again.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kSub, size: 20),
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
            Text('Post Offered Gig',
                style: TextStyle(
                    color: onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: const [ThemeToggleButton()],
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
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────
                _SectionLabel('Description'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _descCtrl,
                  hint: 'Describe the task, expectations, and any special notes...',
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Enter a valid amount';
                    return null;
                  },
                  prefix: const Text(r'$ ',
                      style: TextStyle(
                          color: _kPurple,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),

                // ── Schedule ──────────────────────────────────────
                Row(
                  children: [
                    Text('Schedule',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kSub.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kSub.withValues(alpha: 0.25)),
                      ),
                      child: const Text('Optional',
                          style: TextStyle(
                              color: kSub,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)),
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
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _posting ? 'Sending Offer...' : 'Send Offered Gig',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kPurple.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
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
    final hasWorker = _selectedWorker != null;

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
                Icons.person_search_rounded,
                color: hasWorker ? _kPurple : kSub,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: hasWorker
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedWorker!.name,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedWorker!.email,
                          style: const TextStyle(color: kSub, fontSize: 12),
                        ),
                      ],
                    )
                  : const Text(
                      'Search by name or ID...',
                      style: TextStyle(color: kSub, fontSize: 14),
                    ),
            ),
            Icon(
              hasWorker ? Icons.swap_horiz_rounded : Icons.keyboard_arrow_down_rounded,
              color: kSub,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Skill Dropdown ────────────────────────────────────────────────────────────
  Widget _buildSkillDropdown() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cardColor,
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
          hint: const Text('Select a skill...', style: TextStyle(color: kSub, fontSize: 14)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kSub),
          style: TextStyle(color: onSurface, fontSize: 14),
          items: _kSkills.map((skill) => DropdownMenuItem(
            value: skill,
            child: Text(skill, style: TextStyle(color: onSurface, fontSize: 14)),
          )).toList(),
          onChanged: (v) => setState(() => _selectedSkill = v),
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
        border: Border.all(
          color: _kPurple.withValues(alpha: 0.6),
          width: 1.5,
        ),
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
                  Text(lvLabel,
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Text('• $lvSub',
                      style: const TextStyle(color: kSub, fontSize: 12)),
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
    final dateLabel =
        dateSet ? DateFormat('EEE, MMM d').format(_scheduledDate!) : 'Pick a date';
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
                  color: dateSet ? _kPurple.withValues(alpha: 0.6) : borderColor,
                  width: dateSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      color: dateSet ? _kPurple : kSub, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: TextStyle(
                        color: dateSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight: dateSet ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dateSet)
                    GestureDetector(
                      onTap: () => setState(() => _scheduledDate = null),
                      child: const Icon(Icons.close_rounded, color: kSub, size: 14),
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
                  color: timeSet ? _kPurple.withValues(alpha: 0.6) : borderColor,
                  width: timeSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      color: timeSet ? _kPurple : kSub, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      timeLabel,
                      style: TextStyle(
                        color: timeSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight: timeSet ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (timeSet)
                    GestureDetector(
                      onTap: () => setState(() => _scheduledTime = null),
                      child: const Icon(Icons.close_rounded, color: kSub, size: 14),
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
                  color: (_useMapLocation
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
                                color: _kPurple, strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Detecting location...',
                              style: TextStyle(color: kSub, fontSize: 13)),
                        ],
                      )
                    : hasError
                        ? Text(_locationError!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _address.isNotEmpty
                                    ? _address
                                    : 'Location ready',
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
                  setState(() => _useMapLocation = false);
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
        hintStyle: TextStyle(color: textColor.withValues(alpha: 0.35), fontSize: 14),
        prefix: prefix,
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerPickerSheet extends StatefulWidget {
  final String? excludeUid;
  const _WorkerPickerSheet({this.excludeUid});

  @override
  State<_WorkerPickerSheet> createState() => _WorkerPickerSheetState();
}

class _WorkerPickerSheetState extends State<_WorkerPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_WorkerEntry> _allWorkers = [];
  List<_WorkerEntry> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final workers = snap.docs
          .where((d) => d.id != widget.excludeUid)
          .map((d) => _WorkerEntry(
                uid: d.id,
                name: d.data()['name'] ?? 'Unknown',
                email: d.data()['email'] ?? '',
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _allWorkers = workers;
        _filtered = workers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allWorkers
          .where((w) =>
              w.name.toLowerCase().contains(q) ||
              w.email.toLowerCase().contains(q) ||
              w.uid.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;
    const purple = _kPurple;

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
          Text('Select Gig Worker',
              style: TextStyle(
                  color: onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Search by name, email, or worker ID',
              style: TextStyle(color: kSub, fontSize: 12)),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            style: TextStyle(color: onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search workers...',
              hintStyle: TextStyle(
                  color: onSurface.withValues(alpha: 0.35), fontSize: 14),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: kSub, size: 20),
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
                ? const Center(
                    child: CircularProgressIndicator(color: purple),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_outlined,
                                color: kSub.withValues(alpha: 0.5), size: 40),
                            const SizedBox(height: 10),
                            const Text('No workers found',
                                style: TextStyle(color: kSub, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: borderColor, height: 1),
                        itemBuilder: (_, i) {
                          final w = _filtered[i];
                          return ListTile(
                            onTap: () => Navigator.pop(context, w),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: purple.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_rounded,
                                  color: purple, size: 20),
                            ),
                            title: Text(w.name,
                                style: TextStyle(
                                    color: onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(w.email,
                                style: const TextStyle(
                                    color: kSub, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded,
                                color: kSub, size: 18),
                          );
                        },
                      ),
          ),
        ],
      ),
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
    return Text(text,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.bold));
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
  final _mapController = MapController();
  LatLng? _picked;
  String _address = '';
  bool _geocoding = false;

  static final _defaultCenter = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _picked = widget.initialPosition;
      _geocodePosition(widget.initialPosition!);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _geocodePosition(LatLng pos) async {
    if (!mounted) return;
    setState(() => _geocoding = true);
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (!mounted) return;
      String address = 'Selected location';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          if (p.street != null && p.street!.isNotEmpty) p.street,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
            p.administrativeArea,
        ];
        address = parts.join(', ');
      }
      setState(() {
        _address = address;
        _geocoding = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _address = 'Could not get address';
        _geocoding = false;
      });
    }
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _picked = point;
      _address = '';
    });
    _geocodePosition(point);
  }

  void _confirm() {
    if (_picked == null) return;
    Navigator.pop(
      context,
      _PickedLocation(
        position: _picked!,
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kSub, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Select Location',
            style: TextStyle(
                color: onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialPosition ?? _defaultCenter,
              initialZoom: 14.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.giggre.app',
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 40,
                      height: 50,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: purple,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: purple.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.location_on_rounded,
                                color: Colors.white, size: 18),
                          ),
                          CustomPaint(
                            painter: _TrianglePainter(color: purple),
                            size: const Size(10, 7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_picked == null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.96),
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
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: purple.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.touch_app_rounded,
                          color: purple, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tap anywhere on the map to drop a pin at the gig location',
                        style:
                            TextStyle(color: onSurface, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_picked != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
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
                          child: const Icon(Icons.location_on_rounded,
                              color: purple, size: 20),
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
                                          color: purple, strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Getting address...',
                                        style: TextStyle(
                                            color: kSub, fontSize: 13)),
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
                                          fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    const Text('Tap map to reposition pin',
                                        style: TextStyle(
                                            color: kSub, fontSize: 11)),
                                  ],
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _geocoding ? null : _confirm,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Confirm Location',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: purple.withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
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
              border: Border.all(color: _kPurple.withValues(alpha: 0.5), width: 2),
            ),
            child:
                const Icon(Icons.send_rounded, color: _kPurple, size: 38),
          ),
          const SizedBox(height: 20),
          Text('Offered Gig Sent!',
              style: TextStyle(
                  color: onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
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
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('View My Gigs',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
