import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../utils/user_utils.dart';
import 'register_screen.dart';
import '../../../services/sound_service.dart';

// ── Design tokens (shared accents — identical across light/dark) ───────────
const _kGold = Color(0xFFF0A830);
const _kGoldDeep = Color(0xFFD88810);
const _kSignupGoldLight = Color(0xFFB06E00);
const _kBlueAccent = Color(0xFF2B6FB5);

const _kRow1 = ['briefcase', 'hammer', 'box', 'chefhat'];
const _kRow2 = ['hardhat', 'laptop', 'roller', 'toolbox'];
const _kRow3 = ['wrench', 'broom', 'clipboard', 'basket'];
const _kAllTiles = [..._kRow1, ..._kRow2, ..._kRow3];

class LoginScreen extends StatefulWidget {
  final String? errorMessage;
  const LoginScreen({super.key, this.errorMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading         = false;
  bool isGoogleLoading   = false;
  bool _obscurePassword  = true;
  late String _error;
  bool _precached = false;

  static const _blue   = Color(0xFF1B6CA8);

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

      final docData = doc.data() ?? {};
      final provider = context.read<CurrentUserProvider>();
      provider.setCurrentUserInfo(
        cred.user?.email,
        docData['name'],
        uid,
        docData['userId'],
        docData['isVerified'],
      );
      provider.initCurrencyCode(uid, docData);
      _navigateByRole(docData['role']);

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
        final googleUser = await GoogleSignIn(
          serverClientId: '770115931871-jivlg6kqm5it9n07co1kjhf3vkjj3on3.apps.googleusercontent.com',
        ).signIn();
        if (googleUser == null) { setState(() => isGoogleLoading = false); return; }
        final googleAuth = await googleUser.authentication;
        final idToken     = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;
        if (idToken == null && accessToken == null) {
          throw Exception('Failed to obtain Google credentials. Please try again.');
        }
        final credential = GoogleAuthProvider.credential(
          accessToken: accessToken,
          idToken:     idToken,
        );

        // Check whether this email already has an account *before* touching
        // Firebase Auth. If it doesn't, this is really a sign-up — send the
        // user straight to the name/phone/referral form (no Register screen
        // needed) without creating an Auth account until they finish it.
        final existingQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: googleUser.email)
            .limit(1)
            .get();

        if (existingQuery.docs.isEmpty) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CompleteProfileScreen.pendingGoogleAccount(
                  pendingCredential: credential,
                  pendingDisplayName: googleUser.displayName,
                  pendingPhotoUrl: googleUser.photoUrl,
                ),
              ),
            );
          }
          return;
        }

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
  void initState() {
    super.initState();
    _error = widget.errorMessage ?? '';
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Permission.notification.request();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final name in _kAllTiles) {
      precacheImage(AssetImage('assets/welcome/tile_$name.png'), context);
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
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    return Scaffold(
      backgroundColor: tokens.screenBg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _IconMarquee(tokens: tokens)),
          Align(
            alignment: Alignment.bottomCenter,
            child: _LoginPanel(
              tokens: tokens,
              emailController: emailController,
              passwordController: passwordController,
              obscurePassword: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              error: _error,
              isLoading: isLoading,
              isGoogleLoading: isGoogleLoading,
              onLogin: () { SoundService.tap(); login(); },
              onForgotPassword: () { SoundService.tap(); _sendPasswordReset(); },
              onGoogleTap: signInWithGoogle,
              onSignUp: () {
                SoundService.tap();
                Navigator.pushNamed(context, '/register');
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Icon marquee — three auto-scrolling rows of 3D icon tiles.
// ─────────────────────────────────────────────────────────────────────────────
class _IconMarquee extends StatelessWidget {
  final ProfileTabTokens tokens;
  const _IconMarquee({required this.tokens});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: tokens.screenBg,
      child: Stack(
        children: [
          Positioned(
            top: topPad + 30,
            left: 0,
            right: 0,
            height: 98,
            child: const _MarqueeRow(
              tileNames: _kRow1,
              speed: 18,
              reverse: true,
              initialOffset: 0,
            ),
          ),
          Positioned(
            top: topPad + 144,
            left: 0,
            right: 0,
            height: 98,
            child: const _MarqueeRow(
              tileNames: _kRow2,
              speed: 26,
              reverse: false,
              initialOffset: 47,
            ),
          ),
          Positioned(
            top: topPad + 258,
            left: 0,
            right: 0,
            height: 98,
            child: const _MarqueeRow(
              tileNames: _kRow3,
              speed: 21,
              reverse: true,
              initialOffset: 23,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueeRow extends StatefulWidget {
  final List<String> tileNames;
  final double speed; // px/sec
  final bool reverse;
  final double initialOffset;

  const _MarqueeRow({
    required this.tileNames,
    required this.speed,
    required this.reverse,
    required this.initialOffset,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollCtrl;
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController(initialScrollOffset: widget.initialOffset);
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_onTick)
      ..repeat();
  }

  void _onTick() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.offset + widget.speed / 60);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListView.builder(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        reverse: widget.reverse,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 1000,
        itemBuilder: (_, i) =>
            _MarqueeTile(name: widget.tileNames[i % widget.tileNames.length]),
      ),
    );
  }
}

class _MarqueeTile extends StatelessWidget {
  final String name;
  const _MarqueeTile({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/welcome/tile_$name.png',
          width: 98,
          height: 98,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom login panel
// ─────────────────────────────────────────────────────────────────────────────
class _LoginPanel extends StatelessWidget {
  final ProfileTabTokens tokens;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String error;
  final bool isLoading;
  final bool isGoogleLoading;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogleTap;
  final VoidCallback onSignUp;

  const _LoginPanel({
    required this.tokens,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.error,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.onLogin,
    required this.onForgotPassword,
    required this.onGoogleTap,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final signupGold = isDark ? _kGold : _kSignupGoldLight;

    return Container(
      width: double.infinity,
      height: 500 + bottomSafe,
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(11, 22, 38, 0.10),
            offset: const Offset(0, -14),
            blurRadius: 36,
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset('assets/images/logo.png', height: 34),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome back!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Find your next gig or hire the perfect help.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
            ),
            const SizedBox(height: 22),

            // ─── EMAIL ───
            _AuthField(
              tokens: tokens,
              controller: emailController,
              hintText: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),

            // ─── PASSWORD ───
            _AuthField(
              tokens: tokens,
              controller: passwordController,
              hintText: 'Password',
              icon: Icons.lock_outline,
              obscureText: obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: tokens.textMuted,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            const SizedBox(height: 14),

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
              const SizedBox(height: 14),
            ],

            // ─── LOGIN BUTTON ───
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  shadowColor: WidgetStateProperty.all(Colors.transparent),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kGold, _kGoldDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Log in',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ─── FORGOT PASSWORD ───
            Center(
              child: TextButton(
                onPressed: onForgotPassword,
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: _kBlueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ─── DIVIDER ───
            Row(children: [
              Expanded(child: Divider(color: tokens.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or continue with',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: tokens.divider)),
            ]),
            const SizedBox(height: 16),

            // ─── SOCIAL LOGO ROW ───
            _SocialLogoRow(
              tokens: tokens,
              onGoogleTap:     onGoogleTap,
              isGoogleLoading: isGoogleLoading,
            ),
            const SizedBox(height: 20),

            // ─── SIGN UP ───
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: TextStyle(color: tokens.textMuted, fontSize: 12.5),
                ),
                GestureDetector(
                  onTap: onSignUp,
                  child: Text(
                    'Sign up',
                    style: TextStyle(
                      color: signupGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final ProfileTabTokens tokens;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;

  const _AuthField({
    required this.tokens,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(fontSize: 14, color: tokens.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(color: tokens.textMuted, fontSize: 14),
          prefixIcon: Icon(icon, color: tokens.textMuted, size: 19),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: tokens.insetBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.cardBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: tokens.cardBorder, width: 1),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: _kBlueAccent, width: 1.4),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Social Logo Row
// ─────────────────────────────────────────────────────
class _SocialLogoRow extends StatefulWidget {
  final ProfileTabTokens tokens;
  final VoidCallback onGoogleTap;
  final bool isGoogleLoading;

  const _SocialLogoRow({
    required this.tokens,
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

  Widget _circle(String key) {
    const double size = 46;
    final bool isComingSoon = key == 'apple' || key == 'facebook';
    final tokens = widget.tokens;

    Widget iconWidget;
    switch (key) {
      case 'google':
        iconWidget = Image.asset('assets/images/g-logo.png', width: 22, height: 22);
        break;
      case 'apple':
        iconWidget = Icon(Icons.apple, size: 24, color: tokens.textSecondary);
        break;
      default:
        iconWidget = Icon(Icons.facebook, size: 24, color: tokens.textSecondary);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComingSoon ? tokens.insetBg : tokens.cardSurface,
            border: isComingSoon
                ? null
                : Border.all(color: tokens.cardBorder, width: 1),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isComingSoon ? null : () => _toggle(key),
            child: Center(child: iconWidget),
          ),
        ),
        if (isComingSoon)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _kGold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'SOON',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: widget.tokens.textPrimary),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: widget.tokens.cardBorder),
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
            _circle('google'),
            const SizedBox(width: 22),
            _circle('apple'),
            const SizedBox(width: 22),
            _circle('facebook'),
          ],
        ),
        _expandedButton(),
      ],
    );
  }
}
