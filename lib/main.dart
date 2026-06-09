import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/screens/chat/chat.dart';
import 'package:giggre_app/screens/maintenance_screen.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'core/widgets/main_navigation.dart';
import 'core/theme/theme_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> callNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CurrentUserProvider.initNotifications();
    FilePicker.platform;
    CurrentUserProvider.navigatorKey = navigatorKey;
  } catch (e) {
    firebaseError = e.toString();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CurrentUserProvider()),
      ],
      child: GiggreApp(firebaseError: firebaseError),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Pre-set to true if there's a cached user so the very first frame shows
  // loading rather than LoginScreen while the Firestore restore runs.
  bool _restoringSession = FirebaseAuth.instance.currentUser != null;
  String? _accountError;
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _doRestore(currentUser);
    }
  }

  // Core restore logic — called both from initState and from the stream path.
  Future<void> _doRestore(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        context.read<CurrentUserProvider>().setCurrentUserInfo(
          user.email,
          doc.data()?['name'],
          user.uid,
          doc.data()?['userId'],
          doc.data()?['isVerified'],
        );
      } else {
        // Document confirmed missing — user has no profile, force sign out.
        // Keep _restoringSession true until the auth stream emits null so the
        // StreamBuilder doesn't schedule another _restoreSession in the gap.
        _accountError =
            'Your account is no longer available. Please contact support.';
        await GoogleSignIn().disconnect();
        await FirebaseAuth.instance.signOut();

        // No profile yet — new user is mid-onboarding (completing profile screen).
        // Keep the auth token alive so CompleteProfileScreen can write to Firestore.
        // Do NOT sign out here; _handlePostSignIn already routed them to CompleteProfileScreen.
        // context.read<CurrentUserProvider>().setCurrentUserInfo(
        //   user.email,
        //   null,
        //   user.uid,
        //   null,
        //   null,
        // );
        return;
      }
    } catch (_) {
      // Firestore unreachable (network or token-refresh timing).
      // Set minimal session from Firebase Auth so the app can open.
      if (mounted) {
        context.read<CurrentUserProvider>().setCurrentUserInfo(
          user.email,
          null,
          user.uid,
          null,
          null,
        );
      }
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  // Called from the stream builder when Firebase has a user but the provider
  // is still empty (e.g. the stream fired before initState's restore finished).
  Future<void> _restoreSession(User user) async {
    if (_restoringSession) return;
    setState(() => _restoringSession = true);
    await _doRestore(user);
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider so a rebuild fires as soon as setCurrentUserInfo runs.
    final provider = context.watch<CurrentUserProvider>();

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            _restoringSession) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Trust the provider over the stream — avoids a LoginScreen flash if
        // Firebase briefly emits null during token refresh on app restart.
        if (provider.isLoggedIn) {
          return const MainNavigation();
        }

        if (snapshot.hasData) {
          // Stream has a user but provider is empty (rare race).
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _restoreSession(snapshot.data!),
          );
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return LoginScreen(errorMessage: _accountError);
      },
    );
  }
}

class _FirebaseErrorScreen extends StatelessWidget {
  final String error;
  const _FirebaseErrorScreen(this.error);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Firebase failed to initialize',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceGate extends StatelessWidget {
  const _MaintenanceGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('general_config')
          .doc('maintenance')
          .snapshots(),
      builder: (context, snapshot) {
        // Hold on splash-style loader until we have a definitive answer
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (data['enabled'] == true) {
            return MaintenanceScreen(
              message:
                  data['message'] as String? ??
                  'We\'re currently performing scheduled maintenance. Please check back shortly.',
              startDate: data['startDate'] as String?,
              endDate: data['endDate'] as String?,
            );
          }
        }

        return const AuthGate();
      },
    );
  }
}

class GiggreApp extends StatelessWidget {
  final String? firebaseError;
  const GiggreApp({super.key, this.firebaseError});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Giggre',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.lightTheme,
      darkTheme: ThemeProvider.darkTheme,
      themeMode: themeProvider.mode,
      home: firebaseError != null
          ? _FirebaseErrorScreen(firebaseError!)
          : const _MaintenanceGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/dashboard': (_) => const MainNavigation(),
        '/gigworker': (_) => const MainNavigation(),
        '/gighost': (_) => const MainNavigation(),
      },
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/chat/') == true) {
          final roomId = settings.name!.split('/').last;
          return MaterialPageRoute(builder: (_) => Chat(roomId: roomId));
        }
        return null;
      },
    );
  }
}
