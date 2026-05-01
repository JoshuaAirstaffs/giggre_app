import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../../../utils/user_utils.dart';
import '../../../core/theme/theme_provider.dart';
import 'register_screen.dart';
import '../../../services/sound_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading         = false;
  bool isGoogleLoading   = false;
  bool _obscurePassword  = true;
  String _error = '';

  static const _blue   = Color(0xFF1B6CA8);
  static const _yellow = Color(0xFFF5A623);

  void _navigateByRole(String? role) {
    if (role == 'gigworker') {
      Navigator.pushReplacementNamed(context, '/gigworker');
    } else if (role == 'gighost') {
      Navigator.pushReplacementNamed(context, '/gighost');
    } else {
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

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

    if (needsNewUserId(data?['userId'] as String?)) {
      final newId = await generateUserId();
      await userRef.update({'userId': newId});
    }

    final freshDoc = await userRef.get();
    if (!mounted) return;
    _navigateByRole(freshDoc.data()?['role']);
  }

  Future<void> login() async {
    final email    = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() { isLoading = true; _error = ''; });

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email, password: password,
      );

      final uid     = cred.user!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc     = await userRef.get();

      if (doc.exists && needsNewUserId(doc.data()?['userId'] as String?)) {
        final newId = await generateUserId();
        await userRef.update({'userId': newId});
      }

      if (!mounted) return;

      context.read<CurrentUserProvider>().setCurrentUserInfo(
        cred.user?.email,
        doc.data()?['name'],
        uid,
        doc.data()?['userId'],
        doc.data()?['isVerified'],
      );
      _navigateByRole(doc.data()?['role']);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':         message = 'No account found with this email.'; break;
        case 'wrong-password':         message = 'Incorrect password. Please try again.'; break;
        case 'invalid-credential':     message = 'Invalid email or password.'; break;
        case 'user-disabled':          message = 'This account has been disabled.'; break;
        case 'too-many-requests':      message = 'Too many failed attempts. Please try again later.'; break;
        case 'network-request-failed': message = 'No internet connection.'; break;
        case 'invalid-email':          message = 'Please enter a valid email address.'; break;
        default:                       message = e.message ?? 'Login failed. Please try again.';
      }
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() { isGoogleLoading = true; _error = ''; });
    try {
      UserCredential userCred;
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        userCred = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) { setState(() => isGoogleLoading = false); return; }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken:     googleAuth.idToken,
        );
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _handlePostSignIn(userCred.user!);

    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Google Sign-In failed.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Google Sign-In failed. Please try again.');
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Password reset email sent! Check your inbox.')),
            ]),
            backgroundColor: _blue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Failed to send reset email.');
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 120),
                const SizedBox(height: 20),
                const Text('Welcome to Giggre!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _blue)),
                const SizedBox(height: 8),
                const Text('Find your next gig or hire the perfect help.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 28),

                // ─── EMAIL ───
                TextField(
                  controller: emailController,
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
                  controller: passwordController,
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
                const SizedBox(height: 16),

                // ─── ERROR ───
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

                // ─── LOGIN BUTTON ───
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () { SoundService.tap(); login(); },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _yellow,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('LOG IN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 14),

                // ─── FORGOT PASSWORD ───
                TextButton(
                  onPressed: () { SoundService.tap(); _sendPasswordReset(); },
                  child: const Text('Forgot Password?', style: TextStyle(color: _blue)),
                ),
                const SizedBox(height: 8),

                // ─── DIVIDER ───
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('sign in with', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
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

                // ─── SIGN UP ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? ", style: TextStyle(color: Colors.grey)),
                    GestureDetector(
                      onTap: () { SoundService.tap(); Navigator.pushNamed(context, '/register'); },
                      child: const Text('Sign Up', style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} // ← end _LoginScreenState

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
    const double size = 52;
    final bool active       = _expanded == key;
    final bool isComingSoon = key == 'apple' || key == 'facebook';
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget iconWidget;
    Color borderColor;
    String label;

    switch (key) {
      case 'google':
        iconWidget  = Image.asset('assets/images/g-logo.png', width: 26, height: 26);
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
                  : Image.asset('assets/images/g-logo.png', width: 22, height: 22),
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

