import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../main.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/presentation/login_screen.dart';

class DeleteAccountService {
  static Future<void> deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await _showWarningDialog(context);
    if (!confirmed || !context.mounted) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final signInMethod = doc.data()?['signInMethod'] as String? ?? 'email';

    if (!context.mounted) return;

    final reauthed = await _reAuthenticate(context, user, signInMethod);
    if (!reauthed || !context.mounted) return;

    // Navigate to login FIRST so all screen subscriptions are disposed
    // before we delete data — prevents permission-denied stream errors.
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }

    // Wait for screens to dispose and cancel their Firestore listeners.
    await Future.delayed(const Duration(milliseconds: 400));

    try {
      await _deleteUserData(user.uid);
      await user.delete();

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                  child: Text('Your account has been successfully deleted.')),
            ]),
            backgroundColor: const Color(0xFF1B6CA8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        _showError(ctx, e.message ?? 'Failed to delete account.');
      }
    } catch (_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        _showError(ctx, 'Something went wrong. Please try again.');
      }
    }
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
                  'This will permanently delete your Giggre account and all personal data linked to it — including your profile, uploaded files, skill requests, and support history.',
                  style: TextStyle(color: kSub, height: 1.5, fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your identity will be anonymized on any shared gig or transaction records to preserve history for other users.',
                  style: TextStyle(color: kSub, height: 1.5, fontSize: 13),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This action cannot be undone.',
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
                  'Delete Account',
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
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await user.reauthenticateWithProvider(provider);
      } else {
        final googleUser = await GoogleSignIn(
          serverClientId: '770115931871-jivlg6kqm5it9n07co1kjhf3vkjj3on3.apps.googleusercontent.com',
        ).signIn();
        if (googleUser == null) return false;
        final googleAuth  = await googleUser.authentication;
        final idToken     = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;
        if (idToken == null && accessToken == null) return false;
        final credential = GoogleAuthProvider.credential(
          accessToken: accessToken,
          idToken: idToken,
        );
        await user.reauthenticateWithCredential(credential);
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        _showError(
            context, 'Google re-authentication failed. Please try again.');
      }
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Full Google Play-compliant data erasure
  //
  //  DELETE  — data the user exclusively owns (no other user depends on it)
  //  ANONYMIZE — shared records where other users still need the transaction
  // ─────────────────────────────────────────────────────────────────────────────
  static Future<void> _deleteUserData(String uid) async {
    final db = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    // ── 1. Storage: profile photo ────────────────────────────────────────────
    try {
      await storage.ref('profile_images/$uid.jpg').delete();
    } catch (_) {}

    // ── 2. Storage: skill-request proof files ────────────────────────────────
    try {
      final list = await storage.ref('skill_requests/$uid').listAll();
      for (final item in list.items) {
        await item.delete().catchError((_) {});
      }
    } catch (_) {}

    // ── 3. Firestore: users/{uid}/documents sub-collection ───────────────────
    try {
      final docSnap = await db
          .collection('users')
          .doc(uid)
          .collection('documents')
          .get();
      for (final d in docSnap.docs) {
        await d.reference.delete().catchError((_) {});
      }
    } catch (_) {}

    // ── 4. Firestore: users/{uid} profile document ───────────────────────────
    await db.collection('users').doc(uid).delete().catchError((_) {});

    // ── 5. Firestore: skill_requests owned by user ────────────────────────────
    await _deleteCollection(
        db.collection('skill_requests').where('userId', isEqualTo: uid));

    // ── 6. Firestore: gig_templates created by user ───────────────────────────
    await _deleteCollection(
        db.collection('gig_templates').where('hostId', isEqualTo: uid));

    // ── 7. Firestore: verification_requests (doc keyed by uid) ────────────────
    await db
        .collection('verification_requests')
        .doc(uid)
        .delete()
        .catchError((_) {});

    // ── 8. Firestore: support_tickets submitted by user ───────────────────────
    await _deleteCollection(
        db.collection('support_tickets').where('userId', isEqualTo: uid));

    // ── 9. Firestore: notifications addressed to user ─────────────────────────
    await _deleteCollection(
        db.collection('notifications').where('userId', isEqualTo: uid));

    // ── 10. Firestore: chat_rooms owned by user (support chats) ──────────────
    await _deleteCollection(
        db.collection('chat_rooms').where('userId', isEqualTo: uid));

    // ── 11. ANONYMIZE: quick_gigs where user was the host ────────────────────
    await _anonymizeCollection(
      db.collection('quick_gigs').where('hostId', isEqualTo: uid),
      {'hostName': 'Deleted User'},
    );

    // ── 12. ANONYMIZE: quick_gigs where user was the assigned worker ──────────
    await _anonymizeCollection(
      db.collection('quick_gigs').where('assignedWorkerId', isEqualTo: uid),
      {'assignedWorkerName': 'Deleted Worker'},
    );

    // ── 13. ANONYMIZE: open_gigs where user was the host ─────────────────────
    await _anonymizeCollection(
      db.collection('open_gigs').where('hostId', isEqualTo: uid),
      {'hostName': 'Deleted User'},
    );

    // ── 14. ANONYMIZE: offered_gigs where user was the host ──────────────────
    await _anonymizeCollection(
      db.collection('offered_gigs').where('hostId', isEqualTo: uid),
      {'hostName': 'Deleted User'},
    );

    // ── 15. ANONYMIZE: offered_gigs where user was the worker ────────────────
    await _anonymizeCollection(
      db.collection('offered_gigs').where('workerId', isEqualTo: uid),
      {'workerName': 'Deleted Worker'},
    );
  }

  // Deletes all documents returned by a query (handles empty results silently).
  static Future<void> _deleteCollection(Query query) async {
    try {
      final snap = await query.get();
      for (final doc in snap.docs) {
        await doc.reference.delete().catchError((_) {});
      }
    } catch (_) {}
  }

  // Updates all documents returned by a query with the given fields.
  static Future<void> _anonymizeCollection(
      Query query, Map<String, dynamic> fields) async {
    try {
      final snap = await query.get();
      for (final doc in snap.docs) {
        await doc.reference.update(fields).catchError((_) {});
      }
    } catch (_) {}
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