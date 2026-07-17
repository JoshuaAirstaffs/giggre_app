import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/screens/app_contents/privacy_policy.dart';
import 'package:giggre_app/screens/app_contents/terms_and_conditions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../utils/user_utils.dart';
import '../../../main.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';
import '../../../services/sound_service.dart';

// Lets _MarqueeRow pause its ticker while a screen (e.g. Terms/Privacy) covers
// this one, and resume when the user comes back.
final RouteObserver<PageRoute<void>> welcomeRouteObserver =
    RouteObserver<PageRoute<void>>();

// ── Design tokens (shared accents — identical across light/dark) ───────────
const _kGold = Color(0xFFF0A830);
const _kGoldDeep = Color(0xFFD88810);
const _kSignupGoldLight = Color(0xFFB06E00);
const _kBlueAccent = Color(0xFF2B6FB5);
const _kSubline = Color(0xFF94A0B0);
const _kMuted2 = Color(0xFFB7C0CD);

const _kRow1 = ['briefcase', 'hammer', 'box', 'chefhat'];
const _kRow2 = ['hardhat', 'laptop', 'roller', 'toolbox'];
const _kRow3 = ['wrench', 'broom', 'clipboard', 'basket'];
const _kRow1Reversed = ['chefhat', 'box', 'hammer', 'briefcase'];
const _kAllTiles = [..._kRow1, ..._kRow2, ..._kRow3];

const _kMarqueeRows = [_kRow1, _kRow2, _kRow3, _kRow1Reversed, _kRow2];
const _kRowSpeeds = [18.0, 26.0, 21.0, 23.0, 19.0];
const _kRowReverse = [true, false, true, false, true];
const _kRowOffsets = [0.0, 25.0, 50.0, 75.0, 100.0];

// ── Country data (same list/format as the standalone signup screen) ───────
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

const _kDefaultCountry = _Country('Philippines', '🇵🇭', '+63');

enum _PanelState { welcome, login, signup }

class WelcomeScreen extends StatefulWidget {
  final String? errorMessage;
  const WelcomeScreen({super.key, this.errorMessage});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  _PanelState _panelState = _PanelState.welcome;

  // ── Login state (unchanged from the original LoginScreen) ──────────────
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool isGoogleLoading = false;
  bool _obscurePassword = true;
  late String _error;
  bool _precached = false;

  static const _blue = Color(0xFF1B6CA8);

  // ── Signup state (unchanged from the original RegisterScreen) ──────────
  final _signupNameController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupReferralController = TextEditingController();
  _Country _selectedCountry = _kDefaultCountry;

  bool _signupIsLoading = false;
  bool _signupIsGoogleLoading = false;
  bool _signupObscurePassword = true;
  String _signupError = '';

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
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final userDoc = await userRef.get();

    if (!mounted) return;

    final data = userDoc.data();

    final bool needsProfile =
        !userDoc.exists ||
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
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() {
      isLoading = true;
      _error = '';
    });

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await userRef.get();

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
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-credential':
          message = 'Invalid email or password.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          message = 'No internet connection.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        default:
          message = e.message ?? 'Login failed. Please try again.';
      }
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
      _error = '';
    });
    try {
      UserCredential userCred;
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        userCred = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleUser = await GoogleSignIn(
          serverClientId:
              '770115931871-jivlg6kqm5it9n07co1kjhf3vkjj3on3.apps.googleusercontent.com',
        ).signIn();
        if (googleUser == null) {
          setState(() => isGoogleLoading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;
        if (idToken == null && accessToken == null) {
          throw Exception(
            'Failed to obtain Google credentials. Please try again.',
          );
        }
        final credential = GoogleAuthProvider.credential(
          accessToken: accessToken,
          idToken: idToken,
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
      if (mounted)
        setState(() => _error = e.message ?? 'Google Sign-In failed.');
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Google Sign-In failed. Please try again.');
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
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Password reset email sent! Check your inbox.'),
                ),
              ],
            ),
            backgroundColor: _blue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'Failed to send reset email.');
    }
  }

  // ── Signup handlers (moved verbatim from RegisterScreen) ───────────────
  Future<void> _signupSignInWithGoogle() async {
    setState(() {
      _signupIsGoogleLoading = true;
      _signupError = '';
    });
    try {
      final googleUser = await GoogleSignIn(
        serverClientId:
            '770115931871-jivlg6kqm5it9n07co1kjhf3vkjj3on3.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) {
        setState(() => _signupIsGoogleLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null && accessToken == null) {
        throw Exception(
          'Failed to obtain Google credentials. Please try again.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );
      // Don't create the Firebase Auth account yet — wait until the user
      // finishes entering their name/phone and taps Create account, so we
      // never leave a half-registered account behind if they lose their
      // connection or back out before finishing (e.g. email turns out to
      // already be registered).
      if (!mounted) return;
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
    } catch (e) {
      if (mounted) {
        setState(
          () => _signupError = 'Google Sign-In failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _signupIsGoogleLoading = false);
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
      final count = (doc.data()?['referrals']?['referrals_count'] ?? 0) as int;
      const milestones = [
        1,
        3,
        5,
        10,
        20,
        30,
        50,
        75,
        100,
        125,
        150,
        175,
        200,
        300,
        350,
        400,
        450,
        500,
        550,
        600,
        700,
        800,
        900,
        1000,
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

  Future<void> _register() async {
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text.trim();
    final name = _signupNameController.text.trim();
    final phone = _signupPhoneController.text.trim();
    final referralCode = _signupReferralController.text.trim().toUpperCase();

    if (email.isEmpty || password.isEmpty || name.isEmpty || phone.isEmpty) {
      setState(() => _signupError = 'All fields are required');
      return;
    }
    if (password.length < 6) {
      setState(() => _signupError = 'Password must be at least 6 characters');
      return;
    }

    final fullPhone = '${_selectedCountry.dialCode}$phone';
    if (!phoneRegex.hasMatch(fullPhone) &&
        !RegExp(r'^\+\d{6,15}$').hasMatch(fullPhone)) {
      setState(() => _signupError = 'Enter a valid phone number.');
      return;
    }

    Map<String, dynamic>? referralData;
    if (referralCode.isNotEmpty) {
      if (referralCode.length != 8) {
        setState(
          () => _signupError =
              'Referral code must be 8 characters (e.g. GX82KL19)',
        );
        return;
      }
      referralData = await _validateReferralCode(referralCode);
      if (referralData == null) {
        setState(
          () => _signupError =
              'Invalid referral code. Please check and try again.',
        );
        return;
      }
    }

    UserCredential? cred;
    try {
      setState(() {
        _signupIsLoading = true;
        _signupError = '';
      });

      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final userId = await generateUserId();
      final newUid = cred.user!.uid;

      final String? referrerId = referralData != null
          ? referralData['userId'] as String
          : null;
      final String? referrerName = referralData != null
          ? referralData['name'] as String?
          : null;

      final batch = FirebaseFirestore.instance.batch();
      final newUserRef = FirebaseFirestore.instance
          .collection('users')
          .doc(newUid);

      batch.set(newUserRef, {
        'userId': userId,
        'email': email,
        'name': name,
        'phone': fullPhone,
        'balance': 0,
        'createdAt': Timestamp.now(),
        'skills': [],
        'openGigsUnlocked': false,
        'signInMethod': 'email',
        'ratingAsWorker': 5.0,
        'ratingAsHost': 5.0,
        'ratingCount': 0,
        'slot': 'AVAILABLE',
        'acceptanceRate': 1.0,
        'isVerified': 'unverified',
        'referredBy': referrerId,
        'referrals': {
          'referral_code': await _generateReferralCode(),
          'referral_level': 0,
          'referrals_count': 0,
          'verified_referrals': 0,
          'not_verified_referrals': 0,
          'pending_referrals': 0,
          'cancelled_referrals': 0,
          'rejected_referrals': 0,
          'referredByUID': referrerId,
          'referredByName': referrerName,
        },
      });

      if (referrerId != null) {
        final referralListRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId)
            .collection('referrals_list')
            .doc(newUid);
        batch.set(referralListRef, {
          'name': name,
          'email': email,
          'joined_at': Timestamp.now(),
          'referral_code_used': referralCode,
          'isVerified': 'unverified',
        });
        final referrerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(referrerId);
        batch.update(referrerRef, {
          'referrals.referrals_count': FieldValue.increment(1),
          'referrals.not_verified_referrals': FieldValue.increment(1),
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
                content: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.white),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Account created successfully! Welcome to Giggre!',
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF1B6CA8),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
      if (mounted) setState(() => _signupError = message);
    } catch (e) {
      // Auth succeeded but Firestore failed — delete the auth account so the
      // email is not permanently locked out.
      await cred?.user?.delete();
      if (mounted) {
        setState(
          () => _signupError = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _signupIsLoading = false);
    }
  }

  void _goToLogin() => setState(() => _panelState = _PanelState.login);
  void _goToSignup() => setState(() => _panelState = _PanelState.signup);
  void _goToWelcome() => setState(() => _panelState = _PanelState.welcome);

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
    _signupNameController.dispose();
    _signupPhoneController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupReferralController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final isWelcome = _panelState == _PanelState.welcome;
    final isPanelOpen = !isWelcome;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final panelHeight =
        (_panelState == _PanelState.signup ? 706.0 : 560.0) + bottomSafe;

    return PopScope(
      canPop: isWelcome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isPanelOpen) _goToWelcome();
      },
      child: Scaffold(
        backgroundColor: tokens.screenBg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const Positioned.fill(child: _Marquee()),

            // Welcome copy + CTAs — fades out as the panel rises.
            IgnorePointer(
              ignoring: isPanelOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: isPanelOpen ? 0 : 1,
                child: _WelcomeContent(
                  tokens: tokens,
                  onCreateAccount: () {
                    SoundService.tap();
                    _goToSignup();
                  },
                  onLogIn: () {
                    SoundService.tap();
                    _goToLogin();
                  },
                ),
              ),
            ),

            // Login/signup panel — slides up over the marquee (which never
            // rebuilds) and animates height when swapping between the two.
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                offset: isWelcome ? const Offset(0, 1) : Offset.zero,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: tokens.cardSurface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromRGBO(11, 22, 38, 0.12),
                        offset: const Offset(0, -14),
                        blurRadius: 36,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity > 250) _goToWelcome();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: tokens.cardBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _panelState == _PanelState.signup
                              ? _SignupPanel(
                                  key: const ValueKey('signup'),
                                  tokens: tokens,
                                  nameController: _signupNameController,
                                  phoneController: _signupPhoneController,
                                  emailController: _signupEmailController,
                                  passwordController: _signupPasswordController,
                                  referralController: _signupReferralController,
                                  selectedCountry: _selectedCountry,
                                  onCountryChanged: (c) =>
                                      setState(() => _selectedCountry = c),
                                  obscurePassword: _signupObscurePassword,
                                  onToggleObscure: () => setState(
                                    () => _signupObscurePassword =
                                        !_signupObscurePassword,
                                  ),
                                  error: _signupError,
                                  isLoading: _signupIsLoading,
                                  isGoogleLoading: _signupIsGoogleLoading,
                                  onCreateAccount: () {
                                    SoundService.tap();
                                    _register();
                                  },
                                  onGoogleTap: _signupSignInWithGoogle,
                                  onLogin: () {
                                    SoundService.tap();
                                    _goToLogin();
                                  },
                                )
                              : _LoginPanel(
                                  key: const ValueKey('login'),
                                  tokens: tokens,
                                  emailController: emailController,
                                  passwordController: passwordController,
                                  obscurePassword: _obscurePassword,
                                  onToggleObscure: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  error: _error,
                                  isLoading: isLoading,
                                  isGoogleLoading: isGoogleLoading,
                                  onLogin: () {
                                    SoundService.tap();
                                    login();
                                  },
                                  onForgotPassword: () {
                                    SoundService.tap();
                                    _sendPasswordReset();
                                  },
                                  onGoogleTap: signInWithGoogle,
                                  onSignUp: () {
                                    SoundService.tap();
                                    _goToSignup();
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Back chip — only tappable/visible while the panel is open.
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: IgnorePointer(
                ignoring: !isPanelOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isPanelOpen ? 1 : 0,
                  child: _BackChip(tokens: tokens, onTap: _goToWelcome),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Welcome state — copy + CTAs over a scrim that fades the lower marquee rows.
// ─────────────────────────────────────────────────────────────────────────────
class _WelcomeContent extends StatelessWidget {
  final ProfileTabTokens tokens;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;
  const _WelcomeContent({
    required this.tokens,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: screenHeight * 0.5,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.28, 1.0],
                  colors: [
                    tokens.screenBg.withValues(alpha: 0),
                    tokens.screenBg,
                    tokens.screenBg,
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 28, 32 + bottomSafe),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 48),
                const SizedBox(height: 22),
                Text(
                  'Every gig, right in your area.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: tokens.textPrimary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find work or hire trusted help near you fast, fair, and local.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onCreateAccount,
                    style:
                        ElevatedButton.styleFrom(
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ).copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            Colors.transparent,
                          ),
                          shadowColor: WidgetStateProperty.all(
                            Colors.transparent,
                          ),
                        ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kGold, _kGoldDeep],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Center(
                        child: Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: onLogIn,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: tokens.cardSurface,
                      side: BorderSide(color: tokens.cardBorder, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Text(
                      'Log in',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackChip extends StatelessWidget {
  final ProfileTabTokens tokens;
  final VoidCallback onTap;
  const _BackChip({required this.tokens, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.cardSurface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.cardBorder, width: 1),
      ),
      elevation: 2,
      shadowColor: const Color.fromRGBO(11, 22, 38, 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.arrow_back, size: 18, color: tokens.textPrimary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Marquee background — five auto-scrolling rows, mounted once for the life
//  of the screen so it never restarts when the panel state changes.
// ─────────────────────────────────────────────────────────────────────────────
class _Marquee extends StatelessWidget {
  const _Marquee();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: List.generate(_kMarqueeRows.length, (i) {
        return Positioned(
          top: topPad + 20 + i * 102,
          left: 0,
          right: 0,
          height: 116,
          child: _MarqueeRow(
            tileNames: _kMarqueeRows[i],
            speed: _kRowSpeeds[i],
            reverse: _kRowReverse[i],
            initialOffset: _kRowOffsets[i],
          ),
        );
      }),
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
    with SingleTickerProviderStateMixin, RouteAware {
  late final ScrollController _scrollCtrl;
  late final AnimationController _ticker;
  PageRoute<void>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController(initialScrollOffset: widget.initialOffset);
    _ticker =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(_onTick)
          ..repeat();
  }

  void _onTick() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.offset + widget.speed / 60);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) welcomeRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      welcomeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => _ticker.stop();

  @override
  void didPopNext() {
    if (!_ticker.isAnimating) _ticker.repeat();
  }

  @override
  void dispose() {
    welcomeRouteObserver.unsubscribe(this);
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
        clipBehavior: Clip.none,
        itemCount: 1000,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Center(
            child: _MarqueeTile(
              name: widget.tileNames[i % widget.tileNames.length],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarqueeTile extends StatelessWidget {
  final String name;
  const _MarqueeTile({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Image.asset('assets/welcome/tile_$name.png', width: 88),
    );
  }
}

Widget _sectionLabel(String label) {
  return Text(
    label.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: _kSubline,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login panel content — same controllers/validators as before.
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
    super.key,
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
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final signupGold = isDark ? _kGold : _kSignupGoldLight;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Image.asset('assets/images/logo.png', height: 32)),
          const SizedBox(height: 14),
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
            'Log in to find your next gig or manage your posts.',
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
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ─── LOGIN BUTTON ───
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : onLogin,
              style:
                  ElevatedButton.styleFrom(
                    backgroundColor: _kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
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
          Row(
            children: [
              Expanded(child: Divider(color: tokens.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or continue with',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: tokens.divider)),
            ],
          ),
          const SizedBox(height: 16),

          // ─── SOCIAL LOGO ROW ───
          _SocialLogoRow(
            tokens: tokens,
            onGoogleTap: onGoogleTap,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Signup panel content — same controllers/validators as the old RegisterScreen.
// ─────────────────────────────────────────────────────────────────────────────
class _SignupPanel extends StatelessWidget {
  final ProfileTabTokens tokens;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController referralController;
  final _Country selectedCountry;
  final ValueChanged<_Country> onCountryChanged;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String error;
  final bool isLoading;
  final bool isGoogleLoading;
  final VoidCallback onCreateAccount;
  final VoidCallback onGoogleTap;
  final VoidCallback onLogin;

  const _SignupPanel({
    super.key,
    required this.tokens,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.passwordController,
    required this.referralController,
    required this.selectedCountry,
    required this.onCountryChanged,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.error,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.onCreateAccount,
    required this.onGoogleTap,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create account',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Join Giggre and start earning today!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Personal Info'),
          const SizedBox(height: 10),
          _AuthField(
            tokens: tokens,
            controller: nameController,
            hintText: 'Full Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          _SignupPhoneRow(
            tokens: tokens,
            controller: phoneController,
            selectedCountry: selectedCountry,
            onCountryChanged: onCountryChanged,
          ),
          const SizedBox(height: 20),

          _sectionLabel('Account Details'),
          const SizedBox(height: 10),
          _AuthField(
            tokens: tokens,
            controller: emailController,
            hintText: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 20),

          Row(
            children: [
              _sectionLabel('Referral Code'),
              const Spacer(),
              const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kMuted2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReferralField(tokens: tokens, controller: referralController),
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
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ─── CREATE ACCOUNT BUTTON ───
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : onCreateAccount,
              style:
                  ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
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
                          'Create account',
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
          const _ConsentLine(),
          const SizedBox(height: 16),

          // ─── DIVIDER ───
          Row(
            children: [
              Expanded(child: Divider(color: tokens.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or sign up with',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: tokens.divider)),
            ],
          ),
          const SizedBox(height: 16),

          // ─── SOCIAL LOGO ROW ───
          _SocialLogoRow(
            tokens: tokens,
            onGoogleTap: onGoogleTap,
            isGoogleLoading: isGoogleLoading,
          ),
          const SizedBox(height: 20),

          // ─── LOG IN ───
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: TextStyle(color: tokens.textMuted, fontSize: 12.5),
              ),
              GestureDetector(
                onTap: onLogin,
                child: const Text(
                  'Log in',
                  style: TextStyle(
                    color: _kBlueAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralField extends StatelessWidget {
  final ProfileTabTokens tokens;
  final TextEditingController controller;
  const _ReferralField({required this.tokens, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(fontSize: 14, color: tokens.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. GX82KL19',
              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 14),
              prefixIcon: Icon(
                Icons.card_giftcard_outlined,
                color: tokens.textMuted,
                size: 19,
              ),
              filled: true,
              fillColor: tokens.insetBg,
              contentPadding: const EdgeInsets.only(top: 14, bottom: 14, right: 104),
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
          // Decorative badge only — IgnorePointer keeps it from ever
          // stealing taps meant for the field underneath.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(240, 168, 48, 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Text(
                  'Earn rewards',
                  style: TextStyle(
                    color: _kSignupGoldLight,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentLine extends StatefulWidget {
  const _ConsentLine();

  @override
  State<_ConsentLine> createState() => _ConsentLineState();
}

class _ConsentLineState extends State<_ConsentLine> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TermsAndConditions()),
      );
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PrivacyPolicy()),
      );
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: _kMuted2,
      decoration: TextDecoration.underline,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 9.5, color: _kMuted2),
          children: [
            const TextSpan(text: "By signing up you agree to Giggre's "),
            TextSpan(text: 'Terms', style: linkStyle, recognizer: _termsTap),
            const TextSpan(text: ' & '),
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: _privacyTap,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Phone row — country prefix box + phone field, same controller/behavior as
//  the old signup screen's country picker.
// ─────────────────────────────────────────────────────────────────────────────
class _SignupPhoneRow extends StatelessWidget {
  final ProfileTabTokens tokens;
  final TextEditingController controller;
  final _Country selectedCountry;
  final ValueChanged<_Country> onCountryChanged;

  const _SignupPhoneRow({
    required this.tokens,
    required this.controller,
    required this.selectedCountry,
    required this.onCountryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountryPrefixBox(
          tokens: tokens,
          selected: selectedCountry,
          onChanged: onCountryChanged,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: TextStyle(fontSize: 14, color: tokens.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Phone number',
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 14),
                filled: true,
                fillColor: tokens.insetBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
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
          ),
        ),
      ],
    );
  }
}

class _CountryPrefixBox extends StatelessWidget {
  final ProfileTabTokens tokens;
  final _Country selected;
  final ValueChanged<_Country> onChanged;
  const _CountryPrefixBox({
    required this.tokens,
    required this.selected,
    required this.onChanged,
  });

  void _openPicker(BuildContext context) {
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
                color: tokens.cardSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select Country',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: TextStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search country...',
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20,
                          color: tokens.textMuted,
                        ),
                        filled: true,
                        fillColor: tokens.insetBg,
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
                              .where(
                                (c) =>
                                    c.name.toLowerCase().contains(
                                      val.toLowerCase(),
                                    ) ||
                                    c.dialCode.contains(val),
                              )
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: tokens.divider),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final country = filtered[i];
                        final isSelected =
                            country.dialCode == selected.dialCode &&
                            country.name == selected.name;
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
                                  ? _kBlueAccent
                                  : tokens.textPrimary,
                            ),
                          ),
                          trailing: Text(
                            country.dialCode,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? _kBlueAccent
                                  : tokens.textMuted,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            onChanged(country);
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
      onTap: () => _openPicker(context),
      child: Container(
        width: 92,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.insetBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.cardBorder, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(selected.flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              selected.dialCode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: tokens.textMuted),
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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
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
        iconWidget = Image.asset(
          'assets/images/g-logo.png',
          width: 22,
          height: 22,
        );
        break;
      case 'apple':
        iconWidget = Icon(Icons.apple, size: 24, color: tokens.textSecondary);
        break;
      default:
        iconWidget = Icon(
          Icons.facebook,
          size: 24,
          color: tokens.textSecondary,
        );
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
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Image.asset(
                      'assets/images/g-logo.png',
                      width: 22,
                      height: 22,
                    ),
              label: Text(
                widget.isGoogleLoading
                    ? 'Signing in...'
                    : 'Continue with Google',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: widget.tokens.textPrimary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: widget.tokens.cardBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
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
