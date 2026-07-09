import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:giggre_app/core/constants/api_keys.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/current_user_provider.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/gig_template_model.dart';
import '../models/open_gig_model.dart';
import 'widgets/template_name_dialog.dart';
import 'widgets/skill_picker_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Experience level options
// ─────────────────────────────────────────────────────────────────────────────
const _kLevels = [
  ('entry', 'Entry Level', 'No prior experience needed'),
  ('intermediate', 'Intermediate', '1–3 years of experience'),
  ('expert', 'Expert', '3+ years of experience'),
];

// ─────────────────────────────────────────────────────────────────────────────
//  Post Open Gig Screen
// ─────────────────────────────────────────────────────────────────────────────
class PostOpenGigScreen extends StatefulWidget {
  final String hostName;
  final GigTemplateModel? template;
  const PostOpenGigScreen({super.key, required this.hostName, this.template});

  @override
  State<PostOpenGigScreen> createState() => _PostOpenGigScreenState();
}

class _PostOpenGigScreenState extends State<PostOpenGigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  // Skills (loaded from Firestore /skills)
  List<Map<String, dynamic>> _skills = [];
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
    _fetchSkills();
    final t = widget.template;
    if (t != null) {
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description;
      if (t.budget > 0) _budgetCtrl.text = t.budget.toStringAsFixed(0);
      if (t.skillRequired.isNotEmpty) _selectedSkill = t.skillRequired;
      if (t.experienceLevel.isNotEmpty) _experienceLevel = t.experienceLevel;
    }
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

      // Reverse geocode via Nominatim (works on web + mobile)
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=${pos.latitude}&lon=${pos.longitude}&format=json',
        );
        final res = await http.get(
          uri,
          headers: {'User-Agent': 'giggre_app/1.0'},
        ).timeout(const Duration(seconds: 10));
        if (!mounted) return;
        String address = 'GPS location ready';
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final addrObj = data['address'] as Map<String, dynamic>?;
          final placeName = data['name'] as String?;
          final displayName = data['display_name'] as String?;
          final parts = [
            if (placeName != null && placeName.isNotEmpty) placeName,
            if (addrObj != null) ...[
              addrObj['road'] ?? addrObj['pedestrian'] ?? addrObj['footway'],
              addrObj['suburb'] ?? addrObj['neighbourhood'],
              addrObj['city'] ?? addrObj['town'] ?? addrObj['village'],
              addrObj['state'],
            ],
          ].whereType<String>().where((s) => s.isNotEmpty).toList();
          if (parts.isNotEmpty) {
            address = parts.join(', ');
          } else if (displayName != null && displayName.isNotEmpty) {
            address = displayName;
          }
        }
        setState(() {
          _gpsAddress = address;
          if (!_useMapLocation) _address = address;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _gpsAddress = 'GPS location ready';
            if (!_useMapLocation) _address = 'GPS location ready';
          });
        }
      }
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
                primary: kBlue,
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
                primary: kBlue,
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

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSkill == null || _selectedSkill!.isEmpty) {
      _showSnack('Please select a required skill.');
      return;
    }

    final hasLocation =
        _useMapLocation ? _mapPosition != null : _gpsPosition != null;
    if (!hasLocation) {
      _showSnack('Location is required. Please enable GPS or select on map.');
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

      final gig = OpenGigModel(
        hostId: uid,
        hostName: widget.hostName,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        requiredSkills: [_selectedSkill!],
        experienceLevel: _experienceLevel,
        budget: double.parse(_budgetCtrl.text.trim()),
        currencyCode: currency,
        location: geoPoint,
        address: _address,
        scheduledDate: scheduledAt,
      );

      await FirebaseFirestore.instance.collection('open_gigs').add(gig.toMap());

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
              child: const Icon(Icons.public_off_rounded, color: Colors.red, size: 40),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      await FirebaseFirestore.instance.collection('gig_templates').add(
        GigTemplateModel(
          hostId: uid,
          gigType: 'open',
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kSub, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_outlined,
                  color: kBlue, size: 17),
            ),
            const SizedBox(width: 10),
            Text('Post Open Gig',
                style: TextStyle(
                    color: onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
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
                // ── Title ────────────────────────────────────────
                _SectionLabel('Title'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _titleCtrl,
                  hint: 'e.g. Build an e-commerce website',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────
                _SectionLabel('Description'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _descCtrl,
                  hint: 'Describe the task, deliverables, and expectations...',
                  maxLines: 4,
                ),
                const SizedBox(height: 20),

                // ── Required Skills ───────────────────────────────
                _SectionLabel('Required Skills'),
                const SizedBox(height: 6),
                Text(
                  'Select the skill required for this gig',
                  style: TextStyle(
                      color: kSub.withValues(alpha: 0.8), fontSize: 12),
                ),
                const SizedBox(height: 12),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
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
                          color: kBlue,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kSub.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: kSub.withValues(alpha: 0.25)),
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
                        : const Icon(Icons.workspace_premium_outlined,
                            size: 18),
                    label: Text(
                      _posting ? 'Posting...' : 'Post Open Gig',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kBlue.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
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
                    label: const Text('Save as Template',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kBlue,
                      side: BorderSide(color: kBlue.withValues(alpha: 0.6)),
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

  // ── Fetch skills from Firestore /skills ────────────────────────────────────
  Future<void> _fetchSkills() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('skills').get();
      final list = snap.docs
          .where((d) => d.id != '_counter')
          .map((d) {
            final data = d.data();
            final name = (data['name'] as String?) ?? d.id;
            return {'name': name, 'category': data['category'] as String? ?? ''};
          })
          .where((s) => (s['name'] as String).isNotEmpty)
          .toList()
        ..sort((a, b) =>
            (a['name'] as String).compareTo(b['name'] as String));
      if (mounted) setState(() => _skills = list);
    } catch (_) {}
  }

  // ── Skill Picker ──────────────────────────────────────────────────────────
  Widget _buildSkillDropdown() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: _skills.isEmpty
          ? null
          : () async {
              final picked = await SkillPickerSheet.show(
                context,
                skills: _skills,
                selectedSkill: _selectedSkill,
                accentColor: kBlue,
              );
              if (picked != null) setState(() => _selectedSkill = picked);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedSkill != null
                ? kBlue.withValues(alpha: 0.6)
                : borderColor,
            width: _selectedSkill != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _skills.isEmpty
                    ? 'Loading skills...'
                    : _selectedSkill ?? 'Select a skill...',
                style: TextStyle(
                  color: _selectedSkill != null ? onSurface : kSub,
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: kSub),
          ],
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
          color: kBlue.withValues(alpha: 0.6),
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
    final dateLabel = dateSet
        ? DateFormat('EEE, MMM d').format(_scheduledDate!)
        : 'Pick a date';
    final timeLabel =
        timeSet ? _scheduledTime!.format(context) : 'Pick a time';

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickDate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: dateSet ? kBlue.withValues(alpha: 0.08) : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: dateSet
                      ? kBlue.withValues(alpha: 0.6)
                      : borderColor,
                  width: dateSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      color: dateSet ? kBlue : kSub, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: TextStyle(
                        color: dateSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight:
                            dateSet ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dateSet)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _scheduledDate = null),
                      child: const Icon(Icons.close_rounded,
                          color: kSub, size: 14),
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
                color: timeSet ? kBlue.withValues(alpha: 0.08) : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: timeSet
                      ? kBlue.withValues(alpha: 0.6)
                      : borderColor,
                  width: timeSet ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      color: timeSet ? kBlue : kSub, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      timeLabel,
                      style: TextStyle(
                        color: timeSet ? onSurface : kSub,
                        fontSize: 13,
                        fontWeight:
                            timeSet ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (timeSet)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _scheduledTime = null),
                      child: const Icon(Icons.close_rounded,
                          color: kSub, size: 14),
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
                          ? kBlue
                          : (hasError ? Colors.redAccent : kBlue))
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
                      ? kBlue
                      : (hasError ? Colors.redAccent : kBlue),
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
                                color: kBlue, strokeWidth: 2),
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
                                style:
                                    TextStyle(color: onSurface, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _useMapLocation
                                    ? 'Map-selected location'
                                    : 'Current GPS location',
                                style: TextStyle(
                                  color: _useMapLocation ? kBlue : kSub,
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
                accentColor: kBlue,
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
                accentColor: kBlue,
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
        hintStyle:
            TextStyle(color: textColor.withValues(alpha: 0.35), fontSize: 14),
        prefix: prefix,
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          borderSide: const BorderSide(color: kBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
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
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal,
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
        _osmController.move(ll.LatLng(_myLocation!.latitude, _myLocation!.longitude), 14.0);
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
          perm == LocationPermission.deniedForever) return;
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
        _osmController.move(ll.LatLng(_myLocation!.latitude, _myLocation!.longitude), 14.0);
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
      final road = (addrObj['road'] ?? addrObj['pedestrian'] ?? addrObj['footway']) as String?;
      if (houseNumber != null && houseNumber.isNotEmpty && road != null && road.isNotEmpty) {
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
    if (addr.containsKey('road') || addr.containsKey('pedestrian') || addr.containsKey('footway')) return 3;
    if (addr.containsKey('suburb') || addr.containsKey('neighbourhood')) return 2;
    if (addr.containsKey('city') || addr.containsKey('town') || addr.containsKey('village')) return 1;
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
    final uri = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/autocomplete/json')
        .replace(queryParameters: {
      'input': input.trim(),
      'key': kGoogleMapsApiKey,
      'components': 'country:ph',
      'location': '${bias.latitude},${bias.longitude}',
      'radius': '50000',
      'language': 'en',
    });
    try {
      final res = await http.get(uri);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        debugPrint(
            '[Places] status=$status msg=${data['error_message'] ?? ''}');
        return;
      }
      final predictions =
          (data['predictions'] as List? ?? []).cast<Map<String, dynamic>>();
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
          Uri.parse('https://maps.googleapis.com/maps/api/place/details/json')
              .replace(queryParameters: {
        'place_id': placeId,
        'fields': 'name,formatted_address,geometry',
        'key': kGoogleMapsApiKey,
        'language': 'en',
      });
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
        _googleMapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(point, 18.0));
      } else if (_osmMapReady) {
        _osmController.move(
            ll.LatLng(point.latitude, point.longitude), 18.0);
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
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search').replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': '5',
          'addressdetails': '1',
        },
      );
      final res = await http.get(uri, headers: {'User-Agent': 'giggre_app/1.0'});
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
      final sorted = List<Map<String, dynamic>>.from(data.cast<Map<String, dynamic>>())
        ..sort((a, b) => _nominatimSpecificity(b).compareTo(_nominatimSpecificity(a)));
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
        _googleMapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 18.0));
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
      final res = await http.get(uri, headers: {'User-Agent': 'giggre_app/1.0'});
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
            position: LatLng(recentLat, recentLng), address: recentAddr);
      }
      if (favLat != null && favLng != null && favAddr != null) {
        _favoriteLocation = _SavedLocation(
            position: LatLng(favLat, favLng), address: favAddr);
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
    setState(() => _favoriteLocation =
        _SavedLocation(position: _picked, address: _address));
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
      _googleMapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(loc.position, 18.0));
    } else if (_osmMapReady) {
      _osmController.move(
          ll.LatLng(loc.position.latitude, loc.position.longitude), 18.0);
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
    setState(() { _picked = center; _showQuickPicks = false; });
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
          _onCameraMoved(LatLng(camera.center.latitude, camera.center.longitude));
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
                    Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
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
                    Text(label,
                        style: TextStyle(
                            color: onSurface.withValues(alpha: 0.55),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3)),
                    Text(address,
                        style: TextStyle(
                            color: onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
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

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kSub, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Select Location',
            style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          _useGoogleMaps
              ? GoogleMap(
                  onMapCreated: (controller) => _googleMapController = controller,
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
                      Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
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
                          fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: kSub, size: 20),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: kBlue, strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  color: kBlue, size: 20),
                              onPressed: _searchAddress,
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
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
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Text(_searchError!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
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
                              (p['structured_formatting'] as Map?)?[
                                  'secondary_text'] as String?;
                          return InkWell(
                            onTap: () => _selectSuggestion(p),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 18, color: kSub),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(mainText,
                                            style: TextStyle(
                                                color: onSurface,
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w500)),
                                        if (secondaryText != null &&
                                            secondaryText.isNotEmpty)
                                          Text(secondaryText,
                                              style: TextStyle(
                                                  color:
                                                      onSurface.withValues(
                                                          alpha: 0.55),
                                                  fontSize: 11)),
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
                  color: _myLocation != null ? kBlue : kSub,
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
                      top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: borderColor)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
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
                            color: kBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: kBlue, size: 20),
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
                                          color: kBlue, strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Getting address...',
                                        style: TextStyle(
                                            color: kSub, fontSize: 13)),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                          color: kSub, fontSize: 10),
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
                                ll.LatLng(_picked.latitude, _picked.longitude),
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
                            foregroundColor: kBlue,
                            side: BorderSide(
                              color: kBlue.withValues(alpha: 0.6),
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
                        label: const Text('Confirm Location',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              kBlue.withValues(alpha: 0.4),
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
              color: kBlue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: kBlue.withValues(alpha: 0.5), width: 2),
            ),
            child: const Icon(Icons.workspace_premium_outlined,
                color: kBlue, size: 38),
          ),
          const SizedBox(height: 20),
          Text('Open Gig Posted!',
              style: TextStyle(
                  color: onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Qualified workers matching your\nrequirements will be notified.',
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
                backgroundColor: kBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('View My Gigs',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
