import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/screens/chat/chat.dart';
import 'package:giggre_app/screens/maintenance_screen.dart';
import 'package:provider/provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'core/widgets/main_navigation.dart';
import 'core/widgets/app_update_checker.dart';
import 'core/theme/theme_provider.dart';
import 'services/delete_acc_service.dart';
import 'core/services/session_tracker_service.dart'; // TEMPORARY — testing only, see file header
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

const String flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> callNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: flavor == 'prod'
          ? prod.DefaultFirebaseOptions.currentPlatform
          : dev.DefaultFirebaseOptions.currentPlatform,
    );
    await CurrentUserProvider.initNotifications();
    FilePicker.platform;
    CurrentUserProvider.navigatorKey = navigatorKey;
    SessionTrackerService.instance.start(); // TEMPORARY — testing only
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
  String _deletionStatus = 'pending_deletion';
  String? _accountError;
  // Set when Firestore is unreachable during restore — shows a retry screen
  // instead of opening the app without completing the pendingDeletion check.
  bool _restoreError = false;
  // UID for which _doRestore has completed — guards against the LoginScreen
  // calling setCurrentUserInfo before _doRestore runs its pendingDeletion check.
  String? _restoredForUid;
  // True when a Firebase Auth session exists but registration was never
  // finished (no Firestore profile yet, or no phone on file) — e.g. the app
  // was closed or lost connection right after Google sign-in completed.
  bool _needsProfile = false;
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
          final reqSnap = await FirebaseFirestore.instance
              .collection('account_delete_requests')
              .where('userId', isEqualTo: user.uid)
              .where('status', whereIn: ['pending_deletion', 'approved'])
              .limit(1)
              .get();
          final status = reqSnap.docs.isNotEmpty
              ? reqSnap.docs.first['status'] as String
              : 'pending_deletion';
          if (mounted) {
            setState(() {
              _pendingDeletion = true;
              _scheduledDeleteAt = ts != null
                  ? (ts as Timestamp).toDate()
                  : null;
              _deletionStatus = status;
              _restoredForUid = user.uid;
            });
          }
          return;
        }

        final phone = data['phone'] as String?;
        if (phone == null || phone.isEmpty) {
          // Account exists in Firebase Auth but registration was never
          // finished — send them to finish their profile instead of
          // dropping them into the app with no name/phone on file.
          if (mounted) {
            setState(() {
              _needsProfile = true;
              _restoredForUid = user.uid;
            });
          }
          return;
        }

        final provider = context.read<CurrentUserProvider>();
        provider.setCurrentUserInfo(
          user.email,
          data['name'],
          user.uid,
          data['userId'],
          data['isVerified'],
        );
        provider.initCurrencyCode(user.uid, data);
        if (mounted) {
          setState(() {
            _needsProfile = false;
            _restoredForUid = user.uid;
          });
        }
      } else {
        // No profile at all yet — same "finish registration" case as above.
        if (mounted) {
          setState(() {
            _needsProfile = true;
            _restoredForUid = user.uid;
          });
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
          return _RestoreErrorScreen(onRetry: () => _doRestore(snapshot.data!));
        }

        // No Firebase user — signed out. Reset all gate state and go to login.
        if (!snapshot.hasData && !provider.isLoggedIn) {
          if (_pendingDeletion || _restoredForUid != null || _restoreError || _needsProfile) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() {
                _pendingDeletion = false;
                _scheduledDeleteAt = null;
                _restoredForUid = null;
                _restoreError = false;
                _needsProfile = false;
              }),
            );
          }
          return LoginScreen(errorMessage: _accountError);
        }

        if (_pendingDeletion) {
          return _PendingDeletionScreen(
            scheduledDeleteAt: _scheduledDeleteAt,
            deletionStatus: _deletionStatus,
            onCancelled: () => setState(() {
              _pendingDeletion = false;
              _scheduledDeleteAt = null;
              _deletionStatus = 'pending_deletion';
            }),
          );
        }

        // Auth account exists but registration was never completed — send
        // them to finish it instead of the Dashboard or Login screen.
        if (_needsProfile && _restoredForUid == FirebaseAuth.instance.currentUser?.uid) {
          return CompleteProfileScreen(user: snapshot.data ?? FirebaseAuth.instance.currentUser!);
        }

        // Trust currentUser (synchronous, already restored by native SDK on
        // cold start) over the stream — authStateChanges() can emit a null
        // first event after a full process restart before it catches up,
        // which previously fell through to LoginScreen despite a valid
        // restored session. Also require _doRestore ran for this user so the
        // pendingDeletion check always runs before we open the home screen.
        if (provider.isLoggedIn && _restoredForUid == FirebaseAuth.instance.currentUser?.uid) {
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
  final String deletionStatus;
  final VoidCallback onCancelled;

  const _PendingDeletionScreen({
    required this.scheduledDeleteAt,
    required this.deletionStatus,
    required this.onCancelled,
  });

  @override
  Widget build(BuildContext context) {
    final isApproved = deletionStatus == 'approved';

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
                child: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isApproved ? 'Account Deletion Approved' : 'Account Pending Deletion',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                isApproved
                    ? 'Your account deletion request has been approved by the admin. The deletion process will be completed after 30 days from the date you submitted your request. After completion, your profile and account details cannot be restored. Your account will be permanently deactivated, and your identity will be anonymized in shared gig records and other related history data.'
                    : 'Your account deletion request is pending admin review. Once approved, the deletion process will be completed after 30 days from the date you submitted your request. You can cancel this request at any time to restore full access.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  height: 1.5,
                ),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel Deletion',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    await CurrentUserProvider.unregisterPushForUid(uid);
                  }
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    await CurrentUserProvider.unregisterPushForUid(uid);
                  }
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
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
