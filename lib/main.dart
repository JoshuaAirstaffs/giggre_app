import 'package:flutter/material.dart';
import 'features/auth/presentation/login_screen.dart';

void main() {
  runApp(const GiggreApp());
}

class GiggreApp extends StatelessWidget {
  const GiggreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giggre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF046BD2),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}