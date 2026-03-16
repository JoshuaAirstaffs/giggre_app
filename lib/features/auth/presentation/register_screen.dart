import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/main_navigation.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final fullNameController = TextEditingController();
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController  = TextEditingController();

  bool isLoading    = false;
  bool showPassword = false;
  bool showConfirm  = false;

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  void register() {
    final fullName = fullNameController.text.trim();
    final email    = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirm  = confirmController.text.trim();

    if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match');
      return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters');
      return;
    }

    setState(() => isLoading = true);

    // Simulate a short delay then navigate (UI only)
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showSnack('Account created! Welcome to Giggre.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: kCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // ── Back + Logo ───────────────────────────────────────────────
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const _GiggreLogoSmall(),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),

              const SizedBox(height: 36),

              const Text(
                'Create account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Join Giggre and start earning today',
                style: TextStyle(color: kSub, fontSize: 14),
              ),

              const SizedBox(height: 32),

              const _FieldLabel('Full Name'),
              const SizedBox(height: 8),
              _DarkField(
                controller: fullNameController,
                hint: 'John Doe',
                icon: Icons.person_rounded,
              ),

              const SizedBox(height: 20),

              const _FieldLabel('Email address'),
              const SizedBox(height: 8),
              _DarkField(
                controller: emailController,
                hint: 'you@example.com',
                icon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 20),

              const _FieldLabel('Password'),
              const SizedBox(height: 8),
              _DarkField(
                controller: passwordController,
                hint: 'Min. 6 characters',
                icon: Icons.lock_rounded,
                obscureText: !showPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: kSub,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => showPassword = !showPassword),
                ),
              ),

              const SizedBox(height: 20),

              const _FieldLabel('Confirm Password'),
              const SizedBox(height: 8),
              _DarkField(
                controller: confirmController,
                hint: 'Re-enter your password',
                icon: Icons.lock_outline_rounded,
                obscureText: !showConfirm,
                suffixIcon: IconButton(
                  icon: Icon(
                    showConfirm
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: kSub,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => showConfirm = !showConfirm),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: kSub, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'By creating an account you agree to our Terms of Service and Privacy Policy.',
                      style: TextStyle(
                          color: kSub, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading ? null : register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAmber,
                    foregroundColor: kBg,
                    disabledBackgroundColor: kAmber.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: kBg,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(color: kSub, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        color: kBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const _DarkField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: kSub, fontSize: 15),
          prefixIcon: Icon(icon, color: kSub, size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

// ── Small inline logo ─────────────────────────────────────────────────────────

class _GiggreLogoSmall extends StatelessWidget {
  const _GiggreLogoSmall();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: 36,
      fit: BoxFit.contain,
    );
  }
}