import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'core/widgets/app_update_checker.dart';
import 'core/theme/theme_provider.dart';
import 'services/delete_acc_service.dart';

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
  bool _pendingDeletion = false;
  DateTime? _scheduledDeleteAt;
  String? _accountError;
  // Set when Firestore is unreachable during restore — shows a retry screen
  // instead of opening the app without completing the pendingDeletion check.
  bool _restoreError = false;
  // UID for which _doRestore has completed — guards against the LoginScreen
  // calling setCurrentUserInfo before _doRestore runs its pendingDeletion check.
  String? _restoredForUid;
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
    if (mounted) setState(() => _restoreError = false);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;

        if (data['pendingDeletion'] == true) {
          final ts = data['scheduledDeleteAt'];
          if (mounted) {
            setState(() {
              _pendingDeletion = true;
              _scheduledDeleteAt =
                  ts != null ? (ts as Timestamp).toDate() : null;
              _restoredForUid = user.uid;
            });
          }
          return;
        }

        context.read<CurrentUserProvider>().setCurrentUserInfo(
          user.email,
          data['name'],
          user.uid,
          data['userId'],
          data['isVerified'],
        );
        if (mounted) setState(() => _restoredForUid = user.uid);
      } else {
        if (mounted) {
          context.read<CurrentUserProvider>().setCurrentUserInfo(
            user.email,
            null,
            user.uid,
            null,
            null,
          );
          setState(() => _restoredForUid = user.uid);
        }
        return;
      }
    } catch (_) {
      // Firestore unreachable — do not open the home screen. The pendingDeletion
      // check must succeed before granting access. Show a retry screen instead.
      if (mounted) setState(() => _restoreError = true);
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

        if (_restoreError && snapshot.hasData) {
          return _RestoreErrorScreen(
            onRetry: () => _doRestore(snapshot.data!),
          );
        }

        // No Firebase user — signed out. Reset all gate state and go to login.
        if (!snapshot.hasData && !provider.isLoggedIn) {
          if (_pendingDeletion || _restoredForUid != null || _restoreError) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() {
                _pendingDeletion = false;
                _scheduledDeleteAt = null;
                _restoredForUid = null;
                _restoreError = false;
              }),
            );
          }
          return LoginScreen(errorMessage: _accountError);
        }

        if (_pendingDeletion) {
          return _PendingDeletionScreen(
            scheduledDeleteAt: _scheduledDeleteAt,
            onCancelled: () => setState(() {
              _pendingDeletion = false;
              _scheduledDeleteAt = null;
            }),
          );
        }

        // Trust the provider over the stream — avoids a LoginScreen flash if
        // Firebase briefly emits null during token refresh on app restart.
        // Also require _doRestore ran for this user so the pendingDeletion
        // check always runs before we open the home screen.
        if (provider.isLoggedIn && _restoredForUid == snapshot.data?.uid) {
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

class _PendingDeletionScreen extends StatelessWidget {
  final DateTime? scheduledDeleteAt;
  final VoidCallback onCancelled;

  const _PendingDeletionScreen({
    required this.scheduledDeleteAt,
    required this.onCancelled,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = scheduledDeleteAt != null
        ? scheduledDeleteAt!.difference(DateTime.now()).inDays + 1
        : 30;
    final dateStr = scheduledDeleteAt != null
        ? '${scheduledDeleteAt!.day}/${scheduledDeleteAt!.month}/${scheduledDeleteAt!.year}'
        : '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_outlined,
                    color: Colors.redAccent, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Account Pending Deletion',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account is scheduled for permanent deletion in $daysLeft day${daysLeft == 1 ? '' : 's'}${dateStr.isNotEmpty ? ' (on $dateStr)' : ''}.',
                style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You can cancel this request to restore full access to your account.',
                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await DeleteAccountService.cancelDeletion(context);
                    onCancelled();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B6CA8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel Deletion',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign Out',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestoreErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _RestoreErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                'Unable to connect',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'A connection is required to verify your account status. Please check your internet connection and try again.',
                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B6CA8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Try Again',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign Out',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
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
      builder: (context, child) =>
          AppUpdateChecker(child: child ?? const SizedBox()),
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
