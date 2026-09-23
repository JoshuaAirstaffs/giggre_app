import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../main.dart';
import 'dashboard_screen.dart';
import 'verification_widgets.dart';
import 'welcome_screen.dart';

// ─────────────────────────────────────────────
//  PhoneVerificationScreen
//
//  Last step of onboarding for every sign-up path (email/password and
//  Google) — phone is always collected, so it's always verified via an SMS
//  OTP (Firebase Phone Auth), linked onto the already-signed-in account.
// ─────────────────────────────────────────────
class PhoneVerificationScreen extends StatefulWidget {
  final String phone; // E.164, e.g. +639171234567

  const PhoneVerificationScreen({super.key, required this.phone});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  String? _verificationId;
  int? _resendToken;
  bool _sending = true;
  bool _verifying = false;
  bool _signingOut = false;
  String _error = '';
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _sendCode();
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _onCodeChanged() {
    if (_codeController.text.length == 6 && !_verifying && !_sending) {
      _verifyCode();
    }
  }

  Future<void> _sendCode({int? forceResendToken}) async {
    setState(() { _sending = true; _error = ''; });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phone,
        forceResendingToken: forceResendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _linkCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _error = _messageForError(e);
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _sending = false;
          });
          _startCooldown();
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _codeFocusNode.requestFocus());
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Failed to send verification code. Please try again.';
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String _messageForError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'invalid-verification-code':
        return 'Incorrect code. Please check and try again.';
      case 'session-expired':
        return 'This code has expired. Please request a new one.';
      default:
        return e.message ?? 'Failed to verify phone number.';
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (_verificationId == null || code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your phone.');
      return;
    }
    setState(() { _verifying = true; _error = ''; });
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    await _linkCredential(credential);
  }

  Future<void> _linkCredential(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.linkWithCredential(credential);
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'phoneVerified': true});
      } catch (_) {
        // Best-effort mirror update — linkWithCredential succeeding is what
        // actually matters; a failed write here just means the mirror flag
        // lags until the next check.
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
      Future.delayed(const Duration(milliseconds: 300), () {
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Welcome to Giggre! Your account is ready.')),
              ]),
              backgroundColor: const Color(0xFF1B6CA8),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = _messageForError(e);
        _codeController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Verification failed. Please try again.';
        _codeController.clear();
      });
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
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final fieldsEnabled = !_sending && !_verifying;

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
                const VerificationIconBadge(icon: Icons.sms_outlined),
                const SizedBox(height: 26),
                Text(
                  'Verify your phone number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _sending
                      ? 'Sending a code to ${widget.phone}...'
                      : "We've sent a 6-digit code to\n${widget.phone}",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: tokens.textMuted, height: 1.4),
                ),
                const SizedBox(height: 28),
                VerificationCard(
                  tokens: tokens,
                  child: Column(
                    children: [
                      _OtpInput(
                        controller: _codeController,
                        focusNode: _codeFocusNode,
                        enabled: fieldsEnabled,
                        tokens: tokens,
                      ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        VerificationErrorBanner(message: _error),
                      ],
                      const SizedBox(height: 20),
                      VerificationGradientButton(
                        label: 'VERIFY',
                        loading: _sending || _verifying,
                        onPressed: (_sending || _verifying) ? null : _verifyCode,
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: (_cooldown > 0 || _sending)
                            ? null
                            : () => _sendCode(forceResendToken: _resendToken),
                        child: Text(
                          _cooldown > 0
                              ? 'Resend code in ${_cooldown}s'
                              : 'Resend code',
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

// ─────────────────────────────────────────────
//  Six-box segmented OTP entry. A single (invisible) TextField backs the
//  real input/focus/clipboard-paste handling — the boxes are purely a
//  reflection of its current text, redrawn on every keystroke.
// ─────────────────────────────────────────────
class _OtpInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ProfileTabTokens tokens;

  const _OtpInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () => focusNode.requestFocus() : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final text = controller.text;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  final filled = i < text.length;
                  final isCursor = i == text.length && enabled;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 46,
                    height: 58,
                    decoration: BoxDecoration(
                      color: tokens.insetBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCursor
                            ? kVerifyBlue
                            : filled
                                ? kVerifyBlue.withValues(alpha: 0.45)
                                : tokens.cardBorder,
                        width: isCursor ? 1.8 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filled ? text[i] : '',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          SizedBox(
            width: 0,
            height: 0,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
