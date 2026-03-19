import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../core/theme/app_colors.dart';
import '../models/quick_gig_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Post Quick Gig Screen
// ─────────────────────────────────────────────────────────────────────────────
class PostQuickGigScreen extends StatefulWidget {
  final String hostName;
  const PostQuickGigScreen({super.key, required this.hostName});

  @override
  State<PostQuickGigScreen> createState() => _PostQuickGigScreenState();
}

class _PostQuickGigScreenState extends State<PostQuickGigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  String? _selectedCategory;
  String _selectedDuration = '1 hour';
  Position? _position;
  String _address = '';
  bool _loadingLocation = false;
  String? _locationError;
  bool _posting = false;

  static const _categories = [
    'Dishwashing',
    'Cleaning',
    'Delivery',
    'Errands',
    'Moving',
    'Gardening',
    'Laundry',
    'Cooking',
    'Pet Care',
    'Other',
  ];

  static const _durations = [
    '1 hour',
    '2 hours',
    '3 hours',
    '4 hours',
    'Half Day',
    'Full Day',
  ];

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Please enable GPS.';
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

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
        _position = position;
        _address = address;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      _showSnack('Please select a category.');
      return;
    }
    if (_position == null) {
      _showSnack('Location is required. Please enable GPS.');
      return;
    }

    setState(() => _posting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final gig = QuickGigModel(
        hostId: uid,
        hostName: widget.hostName,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _selectedCategory!,
        budget: double.parse(_budgetCtrl.text.trim()),
        duration: _selectedDuration,
        location: GeoPoint(_position!.latitude, _position!.longitude),
        address: _address,
        status: 'scanning',
      );

      await FirebaseFirestore.instance
          .collection('quick_gigs')
          .add(gig.toMap());

      if (!mounted) return;
      setState(() => _posting = false);
      _showScanningSheet();
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
        backgroundColor: kCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showScanningSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScanningSheet(
        onDone: () {
          Navigator.pop(context); // close sheet
          Navigator.pop(context); // back to gig host screen
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: kSub, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.flash_on_rounded, color: kAmber, size: 17),
            ),
            const SizedBox(width: 10),
            const Text('Post Quick Gig',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Task Details ────────────────────────────────
                _SectionLabel('Task Details'),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _titleCtrl,
                  label: 'Task Title',
                  hint: 'e.g. Wash dishes after event',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _descCtrl,
                  label: 'Description (optional)',
                  hint: 'Add any details the worker should know...',
                  maxLines: 3,
                ),
                const SizedBox(height: 20),

                // ── Category ─────────────────────────────────────
                _SectionLabel('Category'),
                const SizedBox(height: 10),
                _CategoryGrid(
                  categories: _categories,
                  selected: _selectedCategory,
                  onSelect: (c) => setState(() => _selectedCategory = c),
                ),
                const SizedBox(height: 20),

                // ── Compensation ─────────────────────────────────
                _SectionLabel('Compensation'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _budgetCtrl,
                        label: 'Pay (₱)',
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter pay amount';
                          }
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Enter a valid amount';
                          return null;
                        },
                        prefix: const Text('₱ ',
                            style: TextStyle(
                                color: kAmber,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Duration',
                              style:
                                  TextStyle(color: kSub, fontSize: 12)),
                          const SizedBox(height: 6),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: kCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedDuration,
                                dropdownColor: kCard,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                isExpanded: true,
                                items: _durations
                                    .map((d) => DropdownMenuItem(
                                          value: d,
                                          child: Text(d),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _selectedDuration = v);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Location ─────────────────────────────────────
                _SectionLabel('Location'),
                const SizedBox(height: 10),
                _LocationCard(
                  loading: _loadingLocation,
                  address: _address,
                  error: _locationError,
                  onRefresh: _fetchLocation,
                ),
                const SizedBox(height: 32),

                // ── Submit ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _posting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAmber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      disabledBackgroundColor: kAmber.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Post Quick Gig',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: kSub, fontSize: 12)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: Color(0xFF4A5568), fontSize: 14),
            prefix: prefix,
            filled: true,
            fillColor: kCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kAmber, width: 1.5),
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
            errorStyle:
                const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ),
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
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Category Grid
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryGrid extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CategoryGrid({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSelected = selected == cat;
        return GestureDetector(
          onTap: () => onSelect(cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? kAmber.withValues(alpha: 0.18)
                  : kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? kAmber : kBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              cat,
              style: TextStyle(
                color: isSelected ? kAmber : kSub,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Location Card
// ─────────────────────────────────────────────────────────────────────────────
class _LocationCard extends StatelessWidget {
  final bool loading;
  final String address;
  final String? error;
  final VoidCallback onRefresh;

  const _LocationCard({
    required this.loading,
    required this.address,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: error != null
                ? Colors.redAccent.withValues(alpha: 0.5)
                : kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (error != null ? Colors.redAccent : kAmber)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              error != null
                  ? Icons.location_off_outlined
                  : Icons.location_on_rounded,
              color: error != null ? Colors.redAccent : kAmber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: loading
                ? Row(
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: kAmber, strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Detecting location...',
                          style: TextStyle(color: kSub, fontSize: 13)),
                    ],
                  )
                : error != null
                    ? Text(error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            address.isNotEmpty ? address : 'Location detected',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text('Current GPS location',
                              style:
                                  TextStyle(color: kSub, fontSize: 11)),
                        ],
                      ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: kAmber, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Scanning Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _ScanningSheet extends StatefulWidget {
  final VoidCallback onDone;
  const _ScanningSheet({required this.onDone});

  @override
  State<_ScanningSheet> createState() => _ScanningSheetState();
}

class _ScanningSheetState extends State<_ScanningSheet>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _pulseCtrl.stop();
      setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: const BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _done ? _buildSuccess() : _buildScanning(),
      ),
    );
  }

  Widget _buildScanning() {
    return Column(
      key: const ValueKey('scanning'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulse animation
        SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  _PulseCircle(
                      animation: _pulseCtrl, delay: 0.0, color: kAmber),
                  _PulseCircle(
                      animation: _pulseCtrl, delay: 0.33, color: kAmber),
                  _PulseCircle(
                      animation: _pulseCtrl, delay: 0.66, color: kAmber),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: kAmber.withValues(alpha: 0.6), width: 2),
                    ),
                    child: const Icon(Icons.person_search_rounded,
                        color: kAmber, size: 28),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Scanning for Gig Workers...',
          style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Looking for available workers near your location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kAmber.withValues(alpha: 0.3)),
          ),
          child: const Text('Your gig is now live',
              style: TextStyle(
                  color: kAmber, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                width: 2),
          ),
          child: const Icon(Icons.check_rounded,
              color: Color(0xFF22C55E), size: 40),
        ),
        const SizedBox(height: 20),
        const Text(
          'Workers Notified!',
          style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Nearby Gig Workers scanning for quick gigs\nhave been notified about your post.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onDone,
            style: ElevatedButton.styleFrom(
              backgroundColor: kAmber,
              foregroundColor: Colors.black,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pulse Circle Widget
// ─────────────────────────────────────────────────────────────────────────────
class _PulseCircle extends StatelessWidget {
  final Animation<double> animation;
  final double delay;
  final Color color;

  const _PulseCircle({
    required this.animation,
    required this.delay,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        double t = (animation.value + delay) % 1.0;
        final scale = 0.3 + t * 0.7;
        final opacity = (1.0 - t) * 0.5;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: opacity),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}
