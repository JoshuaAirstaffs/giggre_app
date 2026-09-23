import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/profile_tab_theme.dart';
import 'phone_verification_screen.dart';
import 'verification_widgets.dart';
import 'welcome_screen.dart';

// ─────────────────────────────────────────────
//  EmailVerificationScreen
//
//  Shown right after an email/password account is created. Google sign-ups
//  skip this screen entirely — Google already verifies the email address,
//  so their Firestore doc is written with emailVerified: true up front.
// ─────────────────────────────────────────────
class EmailVerificationScreen extends StatefulWidget {
  final String phone;

  const EmailVerificationScreen({super.key, required this.phone});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _checking = false;
  bool _signingOut = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // Covers the case where AuthGate resumes this screen after the user
    // already tapped the email link in a previous session.
    _checkVerified();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified({bool manual = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (manual) setState(() { _checking = true; _error = ''; });

    try {
      await user.reload();
    } catch (_) {
      if (manual && mounted) {
        setState(() {
          _checking = false;
          _error = 'Could not check status. Check your connection and try again.';
        });
      }
      return;
    }

    final refreshed = FirebaseAuth.instance.currentUser;
    if (refreshed != null && refreshed.emailVerified) {
      _pollTimer?.cancel();
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(refreshed.uid)
            .update({'emailVerified': true});
      } catch (_) {
        // Firestore mirror update is best-effort — live emailVerified is the
        // source of truth and will be picked up again on the next check.
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PhoneVerificationScreen(phone: widget.phone),
        ),
      );
    } else if (manual && mounted) {
      setState(() {
        _checking = false;
        _error = "Still not verified. Check your inbox (and spam folder) "
            "for the link, then try again.";
      });
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    setState(() => _error = '');
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      setState(() => _cooldown = 60);
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_cooldown <= 1) {
          t.cancel();
          setState(() => _cooldown = 0);
        } else {
          setState(() => _cooldown--);
        }
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'too-many-requests'
          ? 'Too many requests. Please wait a bit before retrying.'
          : (e.message ?? 'Failed to resend email.'));
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;

    return Scaffold(
      backgroundColor: tokens.screenBg,
      appBar: AppBar(
        backgroundColor: tokens.screenBg,
        elevation: 0,
        leading: _signingOut
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: tokens.textPrimary),
              )
            : IconButton(
                icon: Icon(Icons.logout, color: tokens.textSecondary),
                tooltip: 'Sign out',
                onPressed: _signOut,
              ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 34),
                const SizedBox(height: 28),
                const VerificationIconBadge(icon: Icons.mark_email_unread_outlined),
                const SizedBox(height: 26),
                Text(
                  'Verify your email',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13.5, color: tokens.textMuted, height: 1.4),
                    children: [
                      const TextSpan(text: "We've sent a verification link to\n"),
                      TextSpan(
                        text: email,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                VerificationCard(
                  tokens: tokens,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kVerifyBlue.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Tap the link, then come back here — we'll pick it up automatically.",
                              style: TextStyle(fontSize: 12.5, color: tokens.textMuted, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        VerificationErrorBanner(message: _error),
                      ],
                      const SizedBox(height: 20),
                      VerificationGradientButton(
                        label: "I'VE VERIFIED — CONTINUE",
                        loading: _checking,
                        onPressed: _checking ? null : () => _checkVerified(manual: true),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _cooldown > 0 ? null : _resend,
                        child: Text(
                          _cooldown > 0
                              ? 'Resend email in ${_cooldown}s'
                              : 'Resend verification email',
                          style: TextStyle(
                              color: _cooldown > 0 ? tokens.textMuted : kVerifyBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
