import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../main.dart';
import '../../../utils/user_utils.dart';
import 'dashboard_screen.dart';
import '../../../services/sound_service.dart';

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
  final _nameController  = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String _error = '';

  static const _blue   = Color(0xFF1B6CA8);
  static const _yellow = Color(0xFFF5A623);

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.displayName ?? '';
  }

  Future<void> _saveProfile() async {
    final name  = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and phone number are required.');
      return;
    }
    if (!phoneRegex.hasMatch(phone)) {
      setState(() => _error = 'Enter a valid PH or U.S. phone number.');
      return;
    }

    setState(() { _isLoading = true; _error = ''; });

    try {
      final formattedPhone = formatPhone(phone);
      final userId         = await generateUserId();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
        'userId'          : userId,
        'email'           : widget.user.email ?? '',
        'name'            : name,
        'phone'           : formattedPhone,
        'photoUrl'        : widget.user.photoURL ?? '',
        'balance'         : 0,
        'createdAt'       : Timestamp.now(),
        'skills'          : [],
        'openGigsUnlocked': false,
        'signInMethod'    : 'google',
      });

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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: const BackButton(color: _blue),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Image.asset('assets/images/logo.png', height: 80),
                const SizedBox(height: 16),
                const Text('Complete Your Profile',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _blue)),
                const SizedBox(height: 8),
                Text("Just a few more details and you're all set!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline, color: _blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined, color: _blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                if (_error.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('SAVE & CONTINUE',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController     = TextEditingController();
  final _phoneController    = TextEditingController();

  bool isLoading        = false;
  bool isGoogleLoading  = false;
  bool _obscurePassword = true;
  String error = '';

  static const _blue   = Color(0xFF1B6CA8);
  static const _yellow = Color(0xFFF5A623);

  Future<void> _handlePostSignIn(User user) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
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

    if (data?['userId'] == null) {
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
    setState(() { isGoogleLoading = true; error = ''; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => isGoogleLoading = false); return; }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      await _handlePostSignIn(userCred.user!);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message = 'This email is already registered. Please log in with email instead.'; break;
        case 'network-request-failed':
          message = 'No internet connection.'; break;
        case 'user-disabled':
          message = 'This account has been disabled.'; break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.'; break;
        default:
          message = e.message ?? 'Google Sign-In failed. Please try again.';
      }
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = 'Google Sign-In failed. Please try again.');
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  Future<void> register() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name     = _nameController.text.trim();
    final phone    = _phoneController.text.trim();

    if (email.isEmpty || password.isEmpty || name.isEmpty || phone.isEmpty) {
      setState(() => error = 'All fields are required');
      return;
    }
    if (password.length < 6) {
      setState(() => error = 'Password must be at least 6 characters');
      return;
    }
    if (!phoneRegex.hasMatch(phone)) {
      setState(() => error = 'Enter a valid PH or U.S. phone number.');
      return;
    }

    final formattedPhone = formatPhone(phone);

    try {
      setState(() { isLoading = true; error = ''; });

      final userId = await generateUserId();
      final cred   = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'userId'          : userId,
        'email'           : email,
        'name'            : name,
        'phone'           : formattedPhone,
        'balance'         : 0,
        'createdAt'       : Timestamp.now(),
        'skills'          : [],
        'openGigsUnlocked': false,
        'signInMethod'    : 'email',
      });

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
                  Expanded(child: Text('Account created successfully! Welcome to Giggre!')),
                ]),
                backgroundColor: const Color(0xFF1B6CA8),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':            message = 'This email is already registered.'; break;
        case 'account-exists-with-different-credential': message = 'This email is linked to a Google account.'; break;
        case 'invalid-email':                   message = 'Please enter a valid email address.'; break;
        case 'weak-password':                   message = 'Password must be at least 6 characters.'; break;
        case 'network-request-failed':          message = 'No internet connection.'; break;
        case 'too-many-requests':               message = 'Too many attempts. Please try again later.'; break;
        case 'operation-not-allowed':           message = 'Email registration is currently unavailable.'; break;
        case 'user-disabled':                   message = 'This account has been disabled.'; break;
        default:                                message = e.message ?? 'Registration failed. Please try again.';
      }
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = 'Something went wrong. Please try again.');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 100),
                const SizedBox(height: 16),
                const Text('Create Account',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _blue)),
                const SizedBox(height: 8),
                const Text('Join Giggre and start earning today!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 28),

                // ─── FULL NAME ───
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline, color: _blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── PHONE ───
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined, color: _blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── EMAIL ───
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined, color: _blue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _yellow, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── PASSWORD ───
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: _blue),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),

                // ─── ERROR ───
                if (error.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ─── CREATE ACCOUNT BUTTON ───
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () { SoundService.tap(); register(); },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('CREATE ACCOUNT',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),

                // ─── DIVIDER ───
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or sign up with',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),

                // ─── SOCIAL LOGO ROW ───
                _SocialLogoRow(
                  onGoogleTap:     signInWithGoogle,
                  isGoogleLoading: isGoogleLoading,
                ),
                const SizedBox(height: 24),

                // ─── LOGIN LINK ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ', style: TextStyle(color: Colors.grey)),
                    GestureDetector(
                      onTap: () { SoundService.tap(); Navigator.pop(context); },
                      child: const Text('Log In',
                          style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
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
    const double size   = 52;
    final bool active       = _expanded == key;
    final bool isComingSoon = key == 'apple' || key == 'facebook';
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget iconWidget;
    Color borderColor;
    String label;

    switch (key) {
      case 'google':
        iconWidget  = Image.network(
          'https://developers.google.com/identity/images/g-logo.png',
          height: 26, width: 26,
        );
        borderColor = active ? Colors.redAccent : Colors.grey[300]!;
        label       = 'Google';
        break;
      case 'apple':
        iconWidget  = const Icon(Icons.apple, size: 28, color: Colors.grey);
        borderColor = Colors.grey[300]!;
        label       = 'Apple';
        break;
      default:
        iconWidget  = const Icon(Icons.facebook, size: 28, color: Colors.grey);
        borderColor = Colors.grey[300]!;
        label       = 'Facebook';
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
                border: Border.all(color: borderColor, width: active ? 2 : 1),
                color: isComingSoon
                    ? surfaceVariant
                    : (active ? borderColor.withValues(alpha: 0.07) : surfaceColor),
                boxShadow: active && !isComingSoon
                    ? [BoxShadow(color: borderColor.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))]
                    : [],
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isComingSoon ? () {} : () => _toggle(key),
                child: Center(
                  child: Opacity(opacity: isComingSoon ? 0.4 : 1.0, child: iconWidget),
                ),
              ),
            ),
            if (isComingSoon)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Soon',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
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
              onPressed: widget.isGoogleLoading ? null : widget.onGoogleTap,
              icon: widget.isGoogleLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Image.network(
                      'https://developers.google.com/identity/images/g-logo.png',
                      height: 22, width: 22,
                    ),
              label: Text(
                widget.isGoogleLoading ? 'Signing in...' : 'Continue with Google',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[400]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
