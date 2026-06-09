import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../main.dart';
import '../../../utils/user_utils.dart';
import '../../../core/theme/theme_provider.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import '../../../services/sound_service.dart';
import 'dart:math';

// ─────────────────────────────────────────────
//  Country model & data
// ─────────────────────────────────────────────
class _Country {
  final String name;
  final String flag;
  final String dialCode;
  const _Country(this.name, this.flag, this.dialCode);
}

const List<_Country> _kCountries = [
  _Country('Philippines', '🇵🇭', '+63'),
  _Country('United States', '🇺🇸', '+1'),
  _Country('United Kingdom', '🇬🇧', '+44'),
  _Country('Australia', '🇦🇺', '+61'),
  _Country('Canada', '🇨🇦', '+1'),
  _Country('Singapore', '🇸🇬', '+65'),
  _Country('Japan', '🇯🇵', '+81'),
  _Country('South Korea', '🇰🇷', '+82'),
  _Country('China', '🇨🇳', '+86'),
  _Country('Hong Kong', '🇭🇰', '+852'),
  _Country('Taiwan', '🇹🇼', '+886'),
  _Country('India', '🇮🇳', '+91'),
  _Country('Indonesia', '🇮🇩', '+62'),
  _Country('Malaysia', '🇲🇾', '+60'),
  _Country('Thailand', '🇹🇭', '+66'),
  _Country('Vietnam', '🇻🇳', '+84'),
  _Country('Brunei', '🇧🇳', '+673'),
  _Country('Saudi Arabia', '🇸🇦', '+966'),
  _Country('United Arab Emirates', '🇦🇪', '+971'),
  _Country('Qatar', '🇶🇦', '+974'),
  _Country('Germany', '🇩🇪', '+49'),
  _Country('France', '🇫🇷', '+33'),
  _Country('Italy', '🇮🇹', '+39'),
  _Country('Spain', '🇪🇸', '+34'),
  _Country('Netherlands', '🇳🇱', '+31'),
  _Country('New Zealand', '🇳🇿', '+64'),
];

// Default to Philippines
const _kDefaultCountry = _Country('Philippines', '🇵🇭', '+63');

// ─────────────────────────────────────────────
//  Country Code Picker Widget
// ─────────────────────────────────────────────
class _CountryCodePicker extends StatefulWidget {
  final _Country selected;
  final ValueChanged<_Country> onChanged;
  final bool isDark;

  const _CountryCodePicker({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_CountryCodePicker> createState() => _CountryCodePickerState();
}

class _CountryCodePickerState extends State<_CountryCodePicker> {
  static const _blue = Color(0xFF1B6CA8);

  void _openPicker() {
    final searchCtrl = TextEditingController();
    List<_Country> filtered = List.from(_kCountries);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Select Country',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search country...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                        filled: true,
                        fillColor: widget.isDark
                            ? const Color(0xFF2A2A3A)
                            : const Color(0xFFF7F8FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          filtered = _kCountries
                              .where((c) =>
                                  c.name.toLowerCase().contains(val.toLowerCase()) ||
                                  c.dialCode.contains(val))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  // Country list
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final country = filtered[i];
                        final isSelected =
                            country.dialCode == widget.selected.dialCode &&
                            country.name == widget.selected.name;
                        return ListTile(
                          leading: Text(
                            country.flag,
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(
                            country.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? _blue
                                  : (widget.isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          trailing: Text(
                            country.dialCode,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? _blue : Colors.grey[500],
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            widget.onChanged(country);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF7F8FA),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
          border: Border(
            right: BorderSide(
              color: widget.isDark ? Colors.white12 : Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.selected.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 4),
            Text(
              widget.selected.dialCode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _blue,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Phone field with country picker
// ─────────────────────────────────────────────
class _PhoneField extends StatefulWidget {
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<_Country>? onCountryChanged;

  const _PhoneField({
    required this.controller,
    required this.isDark,
    this.onCountryChanged,
  });

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  _Country _selected = _kDefaultCountry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountryCodePicker(
          selected: _selected,
          isDark: widget.isDark,
          onChanged: (c) {
            setState(() => _selected = c);
            widget.onCountryChanged?.call(c);
          },
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'Phone number',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              filled: true,
              fillColor: widget.isDark
                  ? const Color(0xFF2A2A3A)
                  : const Color(0xFFF7F8FA),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide.none,
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide.none,
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide(color: Color(0xFF1B6CA8), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  CompleteProfileScreen
// ─────────────────────────────────────────────
class CompleteProfileScreen extends StatefulWidget {
  final User user;
  const CompleteProfileScreen({super.key, required this.user});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referralCodeController = TextEditingController();
  _Country _selectedCountry = _kDefaultCountry;
  bool _isLoading = false;
  String _error = '';

  static const _blue = Color(0xFF1B6CA8);
  static const _yellow = Color(0xFFF5A623);

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.displayName ?? '';
  }

  Future<String> _generateReferralCode() async {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digits = '0123456789';
    final rand = Random();
    while (true) {
      final code = [
        letters[rand.nextInt(letters.length)],
        letters[rand.nextInt(letters.length)],
        digits[rand.nextInt(digits.length)],
        digits[rand.nextInt(digits.length)],
        letters[rand.nextInt(letters.length)],
        letters[rand.nextInt(letters.length)],
        digits[rand.nextInt(digits.length)],
        digits[rand.nextInt(digits.length)],
      ].join();
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referrals.referral_code', isEqualTo: code)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return code;
    }
  }

  Future<Map<String, dynamic>?> _validateReferralCode(String code) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referrals.referral_code', isEqualTo: code)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final userDoc = query.docs.first;
        return {
          'userId': userDoc.id,
          'name': userDoc.data()['name'] ?? 'User',
          'email': userDoc.data()['email'] ?? '',
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateReferralLevel(String referrerId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(referrerId)
          .get();
      if (!doc.exists) return;
      final count =
          (doc.data()?['referrals']?['referrals_count'] ?? 0) as int;
      const milestones = [
        1, 3, 5, 10, 20, 30, 50, 75, 100, 125,
        150, 175, 200, 300, 350, 400, 450, 500,
        550, 600, 700, 800, 900, 1000,
      ];
      int level = 0;
      for (int i = 0; i < milestones.length; i++) {
        if (count >= milestones[i]) level = i + 1;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(referrerId)
          .update({'referrals.referral_level': level});
    } catch (e) {
      debugPrint('Failed to update referral level: $e');
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final referralCode = _referralCodeController.text.trim().toUpperCase();

    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and phone number are required.');
      return;
    }

    // Build full phone with country code and validate
    final fullPhone = '${_selectedCountry.dialCode}$phone';
    if (!phoneRegex.hasMatch(fullPhone) && !RegExp(r'^\+\d{6,15}$').hasMatch(fullPhone)) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }

    Map<String, dynamic>? referralData;
    if (referralCode.isNotEmpty) {
      if (referralCode.length != 8) {
        setState(() => _error = 'Referral code must be 8 characters (e.g. GX82KL19)');
        return;
      }
      referralData = await _validateReferralCode(referralCode);
      if (referralData == null) {
        setState(() => _error = 'Invalid referral code. Please check and try again.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userId = await generateUserId();
      final String? referrerId = referralData?['userId'] as String?;
      final String? referrerName = referralData?['name'] as String?;

      final batch = FirebaseFirestore.instance.batch();
      final newUserRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid);

      batch.set(newUserRef, {
        'userId'          : userId,
        'email'           : widget.user.email ?? '',
        'name'            : name,
        'phone'           : fullPhone,
        'photoUrl'        : widget.user.photoURL ?? '',
        'balance'         : 0,
        'createdAt'       : Timestamp.now(),
        'skills'          : [],
        'openGigsUnlocked': false,
        'signInMethod'    : 'google',
        'ratingAsWorker'  : 5.0,
        'ratingAsHost'    : 5.0,
        'ratingCount'     : 0,
        'isVerified'      : 'unverified',
        'referredBy'      : referrerId,
        'referrals'       : {
          'referral_code'         : await _generateReferralCode(),
          'referral_level'        : 0,
          'referrals_count'       : 0,
          'verified_referrals'    : 0,
          'not_verified_referrals': 0,
          'pending_referrals'     : 0,
          'cancelled_referrals'   : 0,
          'rejected_referrals'    : 0,
          'referredByUID'         : referrerId,
          'referredByName'        : referrerName,
        },
      });

      if (referrerId != null) {
        final referralListRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId)
            .collection('referrals_list')
            .doc(widget.user.uid);
        batch.set(referralListRef, {
          'name'              : name,
          'email'             : widget.user.email ?? '',
          'joined_at'         : Timestamp.now(),
          'referral_code_used': referralCode,
          'isVerified'        : 'unverified',
        });
        final referrerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId);
        batch.update(referrerRef, {
          'referrals.referrals_count'        : FieldValue.increment(1),
          'referrals.not_verified_referrals' : FieldValue.increment(1),
        });
        await batch.commit();
        await _updateReferralLevel(referrerId);
      } else {
        await batch.commit();
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          if (navigatorKey.currentContext != null) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              SnackBar(
                content: const Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(child: Text('Profile saved! Welcome to Giggre!')),
                ]),
                backgroundColor: const Color(0xFF1B6CA8),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      // Firestore write failed — sign out and send back to login so the user
      // isn't left authenticated without a profile record.
      await GoogleSignIn().disconnect();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(
              errorMessage: 'Account setup failed. Please sign in again.',
            ),
          ),
          (route) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: Icon(icon, color: _blue, size: 20),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF7F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Colors.grey[400],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: const BackButton(color: _blue),
        actions: const [ThemeToggleButton()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Image.asset('assets/images/logo.png', height: 72),
                const SizedBox(height: 14),
                const Text(
                  'Complete Your Profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _blue,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Just a few more details and you're all set!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 28),

                // ─── FORM CARD ───
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Personal Info'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration(
                          hint: 'Full Name',
                          icon: Icons.person_outline,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PhoneField(
                        controller: _phoneController,
                        isDark: isDark,
                        onCountryChanged: (c) =>
                            setState(() => _selectedCountry = c),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('Referral Code'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _referralCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDecoration(
                          hint: 'e.g. GX82KL19  (Optional)',
                          icon: Icons.card_giftcard_outlined,
                          isDark: isDark,
                        ).copyWith(
                          suffixIcon: ValueListenableBuilder(
                            valueListenable: _referralCodeController,
                            builder: (_, val, __) => val.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close,
                                        size: 18, color: Colors.grey),
                                    onPressed: () =>
                                        _referralCodeController.clear(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          helperText:
                              "Enter a friend's referral code to get started together",
                          helperStyle:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (_error.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text('SAVE & CONTINUE',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  RegisterScreen
// ─────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referralCode = TextEditingController();
  _Country _selectedCountry = _kDefaultCountry;

  bool isLoading = false;
  bool isGoogleLoading = false;
  bool _obscurePassword = true;
  String error = '';

  static const _blue = Color(0xFF1B6CA8);
  static const _yellow = Color(0xFFF5A623);

  Future<void> _handlePostSignIn(User user) async {
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    if (!mounted) return;
    final data = userDoc.data();
    final bool needsProfile = !userDoc.exists ||
        (data?['phone'] == null || (data?['phone'] as String).isEmpty);
    if (needsProfile) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CompleteProfileScreen(user: user)),
      );
      return;
    }
    if (needsNewUserId(data?['userId'] as String?)) {
      final newId = await generateUserId();
      await userRef.update({'userId': newId});
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
      error = '';
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => isGoogleLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _handlePostSignIn(userCred.user!);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message =
              'This email is already registered. Please log in with email instead.';
          break;
        case 'network-request-failed':
          message = 'No internet connection.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        default:
          message = e.message ?? 'Google Sign-In failed. Please try again.';
      }
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted)
        setState(() => error = 'Google Sign-In failed. Please try again.');
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  Future<String> _generateReferralCode() async {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digits = '0123456789';
    final rand = Random();
    while (true) {
      final code = [
        letters[rand.nextInt(letters.length)],
        letters[rand.nextInt(letters.length)],
        digits[rand.nextInt(digits.length)],
        digits[rand.nextInt(digits.length)],
        letters[rand.nextInt(letters.length)],
        letters[rand.nextInt(letters.length)],
        digits[rand.nextInt(digits.length)],
        digits[rand.nextInt(digits.length)],
      ].join();
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referrals.referral_code', isEqualTo: code)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return code;
    }
  }

  Future<Map<String, dynamic>?> _validateReferralCode(String code) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referrals.referral_code', isEqualTo: code)
          .limit(1)
          .get();
      debugPrint('query.docs: ${query.docs.toString()}');
      if (query.docs.isNotEmpty) {
        final userDoc = query.docs.first;
        return {
          'userId': userDoc.id,
          'name': userDoc.data()['name'] ?? 'User',
          'email': userDoc.data()['email'] ?? '',
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateReferralLevel(String referrerId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(referrerId)
          .get();
      if (!doc.exists) return;
      final count =
          (doc.data()?['referrals']?['referrals_count'] ?? 0) as int;
      const milestones = [
        1, 3, 5, 10, 20, 30, 50, 75, 100, 125,
        150, 175, 200, 300, 350, 400, 450, 500,
        550, 600, 700, 800, 900, 1000,
      ];
      int level = 0;
      for (int i = 0; i < milestones.length; i++) {
        if (count >= milestones[i]) level = i + 1;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(referrerId)
          .update({'referrals.referral_level': level});
    } catch (e) {
      debugPrint('Failed to update referral level: $e');
    }
  }

  Future<void> register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final referralCode = _referralCode.text.trim().toUpperCase();

    if (email.isEmpty || password.isEmpty || name.isEmpty || phone.isEmpty) {
      setState(() => error = 'All fields are required');
      return;
    }
    if (password.length < 6) {
      setState(() => error = 'Password must be at least 6 characters');
      return;
    }

    final fullPhone = '${_selectedCountry.dialCode}$phone';
    if (!phoneRegex.hasMatch(fullPhone) &&
        !RegExp(r'^\+\d{6,15}$').hasMatch(fullPhone)) {
      setState(() => error = 'Enter a valid phone number.');
      return;
    }

    Map<String, dynamic>? referralData;
    if (referralCode.isNotEmpty) {
      if (referralCode.length != 8) {
        setState(() =>
            error = 'Referral code must be 8 characters (e.g. GX82KL19)');
        return;
      }
      referralData = await _validateReferralCode(referralCode);
      if (referralData == null) {
        setState(() =>
            error = 'Invalid referral code. Please check and try again.');
        return;
      }
    }

    UserCredential? cred;
    try {
      setState(() {
        isLoading = true;
        error = '';
      });

      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final userId = await generateUserId();
      final newUid = cred.user!.uid;

      final String? referrerId =
          referralData != null ? referralData['userId'] as String : null;
      final String? referrerName =
          referralData != null ? referralData['name'] as String? : null;

      final batch = FirebaseFirestore.instance.batch();
      final newUserRef =
          FirebaseFirestore.instance.collection('users').doc(newUid);

      batch.set(newUserRef, {
        'userId'          : userId,
        'email'           : email,
        'name'            : name,
        'phone'           : fullPhone,
        'balance'         : 0,
        'createdAt'       : Timestamp.now(),
        'skills'          : [],
        'openGigsUnlocked': false,
        'signInMethod'    : 'email',
        'ratingAsWorker'  : 5.0,
        'ratingAsHost'    : 5.0,
        'ratingCount'     : 0,
        'slot'            : 'AVAILABLE',
        'acceptanceRate'  : 1.0,
        'isVerified'      : 'unverified',
        'referredBy'      : referrerId,
        'referrals'       : {
          'referral_code'         : await _generateReferralCode(),
          'referral_level'        : 0,
          'referrals_count'       : 0,
          'verified_referrals'    : 0,
          'not_verified_referrals': 0,
          'pending_referrals'     : 0,
          'cancelled_referrals'   : 0,
          'rejected_referrals'    : 0,
          'referredByUID'         : referrerId,
          'referredByName'        : referrerName,
        },
      });

      if (referrerId != null) {
        final referralListRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId)
            .collection('referrals_list')
            .doc(newUid);
        batch.set(referralListRef, {
          'name'              : name,
          'email'             : email,
          'joined_at'         : Timestamp.now(),
          'referral_code_used': referralCode,
          'isVerified'        : 'unverified',
        });
        final referrerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId);
        batch.update(referrerRef, {
          'referrals.referrals_count'        : FieldValue.increment(1),
          'referrals.not_verified_referrals' : FieldValue.increment(1),
        });
        await batch.commit();
        await _updateReferralLevel(referrerId);
      } else {
        await batch.commit();
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
        Future.delayed(const Duration(milliseconds: 300), () {
          if (navigatorKey.currentContext != null) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              SnackBar(
                content: const Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Account created successfully! Welcome to Giggre!')),
                ]),
                backgroundColor: const Color(0xFF1B6CA8),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered.';
          break;
        case 'account-exists-with-different-credential':
          message = 'This email is linked to a Google account.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'weak-password':
          message = 'Password must be at least 6 characters.';
          break;
        case 'network-request-failed':
          message = 'No internet connection.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        case 'operation-not-allowed':
          message = 'Email registration is currently unavailable.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = e.message ?? 'Registration failed. Please try again.';
      }
      if (mounted) setState(() => error = message);
    } catch (e) {
      // Auth succeeded but Firestore failed — delete the auth account so the
      // email is not permanently locked out.
      await cred?.user?.delete();
      if (mounted)
        setState(() => error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Colors.grey[400],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: Icon(icon, color: _blue, size: 20),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF7F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      decoration: _inputDecoration(hint: hint, icon: icon, isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: const [ThemeToggleButton()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── HEADER ───
                Image.asset('assets/images/logo.png', height: 80),
                const SizedBox(height: 12),
                const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _blue,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Join Giggre and start earning today!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 28),

                // ─── FORM CARD ───
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(isDark ? 0.3 : 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Personal Info'),
                      const SizedBox(height: 10),
                      _field(
                        controller: _nameController,
                        hint: 'Full Name',
                        icon: Icons.person_outline,
                        capitalization: TextCapitalization.words,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                      _PhoneField(
                        controller: _phoneController,
                        isDark: isDark,
                        onCountryChanged: (c) =>
                            setState(() => _selectedCountry = c),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('Account Details'),
                      const SizedBox(height: 10),
                      _field(
                        controller: _emailController,
                        hint: 'Email Address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration(
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          isDark: isDark,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('Referral Code'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _referralCode,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDecoration(
                          hint: 'e.g. GX82KL19  (Optional)',
                          icon: Icons.card_giftcard_outlined,
                          isDark: isDark,
                        ).copyWith(
                          suffixIcon: ValueListenableBuilder(
                            valueListenable: _referralCode,
                            builder: (_, val, __) => val.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close,
                                        size: 18, color: Colors.grey),
                                    onPressed: () => _referralCode.clear(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          helperText:
                              "Enter a friend's referral code to get started together",
                          helperStyle:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ─── ERROR ───
                if (error.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(error,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),

                // ─── CREATE ACCOUNT BUTTON ───
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            SoundService.tap();
                            register();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text('CREATE ACCOUNT',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 20),

                // ─── DIVIDER ───
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or sign up with',
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 16),

                // ─── SOCIAL LOGO ROW ───
                _SocialLogoRow(
                  onGoogleTap: signInWithGoogle,
                  isGoogleLoading: isGoogleLoading,
                ),

                const SizedBox(height: 24),

                // ─── LOGIN LINK ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account? ',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13)),
                    GestureDetector(
                      onTap: () {
                        SoundService.tap();
                        Navigator.pop(context);
                      },
                      child: const Text('Log In',
                          style: TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
} // ← end _RegisterScreenState

// ─────────────────────────────────────────────────────
// Social Logo Row
// ─────────────────────────────────────────────────────
class _SocialLogoRow extends StatefulWidget {
  final VoidCallback onGoogleTap;
  final bool isGoogleLoading;

  const _SocialLogoRow({
    required this.onGoogleTap,
    required this.isGoogleLoading,
  });

  @override
  State<_SocialLogoRow> createState() => _SocialLogoRowState();
}

class _SocialLogoRowState extends State<_SocialLogoRow>
    with SingleTickerProviderStateMixin {
  String? _expanded;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    if (_expanded == key) {
      _ctrl.reverse().then((_) => setState(() => _expanded = null));
    } else {
      setState(() => _expanded = key);
      _ctrl.forward(from: 0);
    }
  }

  Widget _logo(String key) {
    const double size = 52;
    final bool active = _expanded == key;
    final bool isComingSoon = key == 'apple' || key == 'facebook';
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final surfaceVariant =
        Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget iconWidget;
    Color borderColor;
    String label;

    switch (key) {
      case 'google':
        iconWidget = Image.asset('assets/images/g-logo.png',
            width: 26, height: 26);
        borderColor = active ? Colors.redAccent : Colors.grey[300]!;
        label = 'Google';
        break;
      case 'apple':
        iconWidget =
            const Icon(Icons.apple, size: 28, color: Colors.grey);
        borderColor = Colors.grey[300]!;
        label = 'Apple';
        break;
      default:
        iconWidget =
            const Icon(Icons.facebook, size: 28, color: Colors.grey);
        borderColor = Colors.grey[300]!;
        label = 'Facebook';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: borderColor, width: active ? 2 : 1),
                color: isComingSoon
                    ? surfaceVariant
                    : (active
                        ? borderColor.withValues(alpha: 0.07)
                        : surfaceColor),
                boxShadow: active && !isComingSoon
                    ? [
                        BoxShadow(
                            color: borderColor.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]
                    : [],
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isComingSoon ? () {} : () => _toggle(key),
                child: Center(
                  child: Opacity(
                      opacity: isComingSoon ? 0.4 : 1.0,
                      child: iconWidget),
                ),
              ),
            ),
            if (isComingSoon)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('Soon',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: isComingSoon
                ? Colors.grey[400]
                : (active ? borderColor : Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  Widget _expandedButton() {
    if (_expanded != 'google') return const SizedBox.shrink();
    return FadeTransition(
      opacity: _anim,
      child: SizeTransition(
        sizeFactor: _anim,
        axisAlignment: -1,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed:
                  widget.isGoogleLoading ? null : widget.onGoogleTap,
              icon: widget.isGoogleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Image.asset('assets/images/g-logo.png',
                      width: 22, height: 22),
              label: Text(
                widget.isGoogleLoading
                    ? 'Signing in...'
                    : 'Continue with Google',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[400]!),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _logo('google'),
            const SizedBox(width: 20),
            _logo('apple'),
            const SizedBox(width: 20),
            _logo('facebook'),
          ],
        ),
        _expandedButton(),
      ],
    );
  }
}