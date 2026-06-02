import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/screens/chat/chat.dart';
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
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
  bool _restoringSession = false;

  Future<void> _restoreSession(User user) async {
    setState(() => _restoringSession = true);
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
      }
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _restoringSession) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          final provider = context.read<CurrentUserProvider>();
          if (!provider.isLoggedIn) {
            // Firebase has a cached session but provider is empty (app restart).
            // Fetch user data from Firestore before rendering the main screen.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _restoreSession(snapshot.data!),
            );
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const MainNavigation();
        }

        return const LoginScreen();
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
              const Text('Firebase failed to initialize',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ),
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
          : const AuthGate(),
      routes: {
        '/login':     (_) => const LoginScreen(),
        '/register':  (_) => const RegisterScreen(),
        '/dashboard': (_) => const MainNavigation(),
        '/gigworker': (_) => const MainNavigation(),
        '/gighost':   (_) => const MainNavigation(),
      },
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/chat/') == true) {
          final roomId = settings.name!.split('/').last;
          return MaterialPageRoute(
            builder: (_) => Chat(roomId: roomId),
          );
        }
        return null;
      },
    );
  }
}