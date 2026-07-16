import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../core/providers/current_user_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/models/delete_request_model.dart';
import '../features/auth/presentation/login_screen.dart';

class DeleteAccountService {
  // ─────────────────────────────────────────────────────────────────────────────
  //  Request deletion — marks account pending_deletion for 30 days.
  //  Actual data erasure happens server-side via the delete-scheduled-users cron.
  // ─────────────────────────────────────────────────────────────────────────────
  static Future<void> deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await _showWarningDialog(context);
    if (!confirmed || !context.mounted) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final signInMethod =
        userDoc.data()?['signInMethod'] as String? ?? 'email';
    final email = user.email ??
        userDoc.data()?['email'] as String? ??
        '';

    if (!context.mounted) return;

    final reauthed = await _reAuthenticate(context, user, signInMethod);
    if (!reauthed || !context.mounted) return;

    final reasonResult = await _showReasonDialog(context);
    if (reasonResult == null || !context.mounted) return;
    final reason = reasonResult.isEmpty ? null : reasonResult;

    // Write to Firestore BEFORE navigating so active screen listeners are still
    // mounted during the write — prevents dependents.isEmpty assertion errors.
    try {
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final scheduledAt = now.add(const Duration(days: 30));

      final requestRef = db.collection('account_delete_requests').doc();

      await requestRef.set(DeleteRequestModel(
        requestId: requestRef.id,
        userId: user.uid,
        email: email,
        requestedAt: now,
        deletionScheduledAt: scheduledAt,
        status: 'pending_deletion',
        reason: reason,
      ).toMap());

      await db.collection('users').doc(user.uid).update({
        'pendingDeletion': true,
        'scheduledDeleteAt': Timestamp.fromDate(scheduledAt),
      });

      Future<void>? clearing;
      if (context.mounted) {
        clearing = context.read<CurrentUserProvider>().clearUser();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      await clearing;
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[DeleteAccountService] deleteAccount error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to schedule account deletion. Please try again.');
      }
      return;
    }

    // signOut() triggers authStateChanges(null) — AuthGate rebuilds to LoginScreen.
    // Show the snackbar after the frame so it renders on the LoginScreen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your account is scheduled for deletion in 30 days. You can cancel this during that period.',
                ),
              ),
            ]),
            backgroundColor: const Color(0xFF1B6CA8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Cancel a pending deletion request within the 30-day window.
  // ─────────────────────────────────────────────────────────────────────────────
  static Future<void> cancelDeletion(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final db = FirebaseFirestore.instance;

      final snap = await db
          .collection('account_delete_requests')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending_deletion', 'approved'])
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return;

      await snap.docs.first.reference.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      await db.collection('users').doc(user.uid).update({
        'pendingDeletion': FieldValue.delete(),
        'scheduledDeleteAt': FieldValue.delete(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Account deletion has been cancelled.')),
            ]),
            backgroundColor: const Color(0xFF1B6CA8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Failed to cancel deletion. Please try again.');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Dialogs & re-authentication (unchanged)
  // ─────────────────────────────────────────────────────────────────────────────

  static const _kPresetReasons = [
    'I no longer use the app',
    'Privacy concerns',
    'Found a better alternative',
    'Too many notifications',
    'Technical issues',
    'Other',
  ];

  // Returns:
  //   null   → user cancelled (abort deletion)
  //   ''     → user skipped (no reason provided)
  //   String → user's selected/entered reason
  static Future<String?> _showReasonDialog(BuildContext context) async {
    String? selected;
    final otherController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          title: Text(
            'Why are you leaving?',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Optional — helps us improve.',
                  style: TextStyle(color: kSub, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _kPresetReasons
                      .map((reason) => RadioListTile<String>(
                            dense: true,
                            value: reason,
                            title: Text(reason,
                                style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        Theme.of(ctx).colorScheme.onSurface)),
                          ))
                      .toList(),
                ),
              ),
              if (selected == 'Other')
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: otherController,
                    autofocus: true,
                    maxLines: 2,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurface,
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tell us more…',
                      hintStyle:
                          const TextStyle(color: kSub, fontSize: 14),
                      filled: true,
                      fillColor: Theme.of(ctx).scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBlue),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: kSub)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Skip', style: TextStyle(color: kSub)),
            ),
            TextButton(
              onPressed: () {
                final reason = selected == 'Other'
                    ? otherController.text.trim()
                    : selected ?? '';
                Navigator.pop(ctx, reason);
              },
              child: const Text(
                'Continue',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    otherController.dispose();
    return result;
  }

  static Future<bool> _showWarningDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).cardColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your account deletion request will be submitted for admin review and approval. Once approved, your account will be scheduled for deletion.',
                  style: TextStyle(color: kSub, height: 1.5, fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The deletion process will be completed after 30 days from the date you submitted your request. After completion, your profile and account details cannot be restored.',
                  style: TextStyle(color: kSub, height: 1.5, fontSize: 13),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your account will be permanently deactivated, and your identity will be anonymized in shared gig records and other related history data.',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: kSub)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Schedule Deletion',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<bool> _reAuthenticate(
      BuildContext context, User user, String signInMethod) async {
    if (signInMethod == 'google') {
      // On web, Google popup reauth requires OAuth origin registration.
      // Skip reauth on web — Firestore writes don't require it.
      if (kIsWeb) return true;
      return _reAuthWithGoogle(context, user);
    }
    return _reAuthWithEmail(context, user);
  }

  static Future<bool> _reAuthWithEmail(
      BuildContext context, User user) async {
    final passwordController = TextEditingController();
    String localError = '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          title: Text(
            'Confirm Your Identity',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your password to confirm account deletion.',
                style: TextStyle(color: kSub, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: kSub, fontSize: 14),
                  filled: true,
                  fillColor: Theme.of(ctx).scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBlue),
                  ),
                ),
              ),
              if (localError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(localError,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: kSub)),
            ),
            TextButton(
              onPressed: () async {
                final password = passwordController.text.trim();
                if (password.isEmpty) {
                  setState(() => localError = 'Please enter your password.');
                  return;
                }
                try {
                  final credential = EmailAuthProvider.credential(
                      email: user.email!, password: password);
                  await user.reauthenticateWithCredential(credential);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on FirebaseAuthException catch (e) {
                  setState(() => localError =
                      (e.code == 'wrong-password' ||
                              e.code == 'invalid-credential')
                          ? 'Incorrect password.'
                          : (e.message ?? 'Authentication failed.'));
                } catch (_) {
                  setState(() => localError =
                      'Authentication failed. Please try again.');
                }
              },
              child: const Text(
                'Confirm',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();
    return result ?? false;
  }

  static Future<bool> _reAuthWithGoogle(
      BuildContext context, User user) async {
    try {
      const clientId =
          '770115931871-jivlg6kqm5it9n07co1kjhf3vkjj3on3.apps.googleusercontent.com';
      final googleSignIn = GoogleSignIn(
        // clientId required by google_sign_in_web to init the OAuth flow.
        // serverClientId required on Android/iOS to get an idToken in the response.
        // This must match the Web OAuth 2.0 client ID in Firebase Console.
        clientId: kIsWeb ? clientId : null,
        serverClientId: kIsWeb ? null : clientId,
      );

      // Sign out first to force fresh account selection and new tokens —
      // cached sessions return a null idToken which breaks reauth on Android.
      try {
        await googleSignIn.signOut();
      } catch (_) {
        // signOut failure is non-fatal; proceed to signIn.
      }

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return false; // user dismissed picker

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      // Firebase Auth on Android requires idToken — accessToken alone is not enough.
      if (idToken == null) {
        debugPrint(
          '[DeleteAccountService] Google reauth: idToken is null. '
          'Verify serverClientId matches the Web OAuth client in Firebase Console '
          'and the SHA-1 fingerprint is registered.',
        );
        if (context.mounted) {
          _showError(context, 'Google re-authentication failed. Please try again.');
        }
        return false;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      debugPrint('[DeleteAccountService] Google reauth error: $e');
      final eStr = e.toString();
      final isCancelled = eStr.contains('popup_closed') ||
          eStr.contains('user_cancelled') ||
          eStr.contains('sign_in_cancelled') ||
          eStr.contains('sign_in_failed');
      final isNetwork = eStr.contains('network_error');
      if (!isCancelled && context.mounted) {
        _showError(
          context,
          isNetwork
              ? 'No internet connection. Please check your network and try again.'
              : 'Google re-authentication failed. Please try again.',
        );
      }
      return false;
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ]),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
