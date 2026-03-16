import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/main_navigation.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading    = false;
  bool showPassword = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login() {
    final email    = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => isLoading = true);

    // Simulate network delay then navigate (UI only — no real auth)
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => isLoading = false);
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
              const SizedBox(height: 60),

              // ── Logo ──────────────────────────────────────────────────────
              const Center(child: _GiggreLogo()),

              const SizedBox(height: 48),

              // ── Email field ───────────────────────────────────────────────
              const _FieldLabel('Email address'),
              const SizedBox(height: 8),
              _DarkField(
                controller: emailController,
                hint: 'you@example.com',
                icon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 20),

              // ── Password field ────────────────────────────────────────────
              const _FieldLabel('Password'),
              const SizedBox(height: 8),
              _DarkField(
                controller: passwordController,
                hint: '••••••••',
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

              const SizedBox(height: 10),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Forgot password?',
                  style: TextStyle(color: kBlue, fontSize: 13),
                ),
              ),

              const SizedBox(height: 32),

              // ── Login button ──────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading ? null : login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kBlue.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Divider ───────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(child: Divider(color: kBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(color: kSub, fontSize: 13),
                    ),
                  ),
                  Expanded(child: Divider(color: kBorder)),
                ],
              ),

              const SizedBox(height: 20),

              // ── Social login buttons ──────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _SocialButton(
                      label: 'Google',
                      icon: const _GoogleIcon(),
                      onTap: () => _showSnack('Google sign-in coming soon'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SocialButton(
                      label: 'Apple',
                      icon: const Icon(Icons.apple_rounded, color: Colors.white, size: 22),
                      onTap: () => _showSnack('Apple sign-in coming soon'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SocialButton(
                      label: 'Facebook',
                      icon: const _FacebookIcon(),
                      onTap: () => _showSnack('Facebook sign-in coming soon'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // ── Register link ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: kSub, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: kAmber,
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

// ── Giggre Logo Widget ────────────────────────────────────────────────────────
//
// HOW TO USE A REAL IMAGE:
//   1. Drop your logo file into  assets/images/logo.png
//   2. Change `_useImageLogo` to true below.
//   3. Run `flutter pub get` — done!
//
const bool _useImageLogo = true; // ← flip to true once logo.png is in assets

class _GiggreLogo extends StatelessWidget {
  const _GiggreLogo();

  @override
  Widget build(BuildContext context) {
    if (_useImageLogo) {
      return Column(
        children: [
          Image.asset(
            'assets/images/logo.png',
            height: 80,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 10),
          Text(
            'Connecting tasks with talent',
            style: TextStyle(color: kSub, fontSize: 12, letterSpacing: 0.3),
          ),
        ],
      );
    }

    // Default: text-based logo (used until real image is added)
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PersonBubble(color: kBlue),
            const SizedBox(width: 6),
            _PersonBubble(color: kAmber),
          ],
        ),
        const SizedBox(height: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: 'gi', style: TextStyle(color: kBlue)),
              TextSpan(text: 'gg', style: TextStyle(color: kAmber)),
              TextSpan(text: 're', style: TextStyle(color: kBlue)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Connecting tasks with talent',
          style: TextStyle(color: kSub, fontSize: 12, letterSpacing: 0.3),
        ),
      ],
    );
  }
}

class _PersonBubble extends StatelessWidget {
  final Color color;
  const _PersonBubble({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Icon(Icons.person_rounded, color: color, size: 26),
    );
  }
}

// ── Social Login Widgets ──────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: kSub, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google "G" logo drawn with colored quadrants.
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Draw colored arcs (blue, red, yellow, green)
    final colors = [
      const Color(0xFF4285F4), // blue  — top-right
      const Color(0xFFEA4335), // red   — top-left
      const Color(0xFFFBBC05), // yellow — bottom-left
      const Color(0xFF34A853), // green  — bottom-right
    ];
    for (int i = 0; i < 4; i++) {
      final paint = Paint()..color = colors[i]..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        (i * 90 - 90) * (3.14159 / 180),
        90 * (3.14159 / 180),
        true,
        paint,
      );
    }

    // White center circle to create ring effect
    canvas.drawCircle(c, r * 0.55, Paint()..color = kCard);

    // Blue "G" bar on the right
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - r * 0.22, r * 0.95, r * 0.44),
      barPaint,
    );

    // Re-draw white center to clip the bar neatly
    canvas.drawCircle(c, r * 0.55, Paint()..color = kCard);

    // Final inner white circle
    canvas.drawCircle(c, r * 0.38, Paint()..color = kCard);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Facebook "f" icon.
class _FacebookIcon extends StatelessWidget {
  const _FacebookIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Color(0xFF1877F2),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'f',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}