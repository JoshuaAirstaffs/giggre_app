import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/welcome_screen.dart';
import '../providers/current_user_provider.dart';

/// The sign-out teardown chain, with no navigation and no [BuildContext] —
/// shared by every logout entry point, including the ones that must not
/// navigate (main.dart's pendingDeletion/restoreError screens, which AuthGate
/// itself renders: pushing over them would tear down the very gate that
/// decides what replaces them).
///
/// The ordering is load-bearing. Any step that throws or stalls strands the
/// user signed in with a dead-looking button, so every step before
/// [FirebaseAuth.signOut] is both caught and time-bounded.
///
/// [revokeGoogle] revokes the Google grant outright, which forces a full
/// consent prompt on the next sign-in rather than a one-tap account pick. Only
/// the call sites that already did this pass true; it stays opt-in so wiring a
/// new path through here can't silently change its sign-in UX.
Future<void> signOutAndCleanup(
  CurrentUserProvider provider, {
  bool revokeGoogle = false,
}) async {
  // clearUser() keys its FCM unregister off the provider's own uid, which is
  // still null on the paths that sign out before setCurrentUserInfo ever ran
  // (_doRestore returns early for pendingDeletion and on restore failure).
  // Fall back to FirebaseAuth's uid there, or the device token stays on the
  // outgoing user's doc and they keep getting this device's pushes.
  final providerUid = provider.uid;
  final uid = providerUid ?? FirebaseAuth.instance.currentUser?.uid;

  await provider.clearUser();

  if (providerUid == null && uid != null) {
    await CurrentUserProvider.unregisterPushForUid(uid);
  }

  if (revokeGoogle) {
    // disconnect() throws when the current session isn't a Google sign-in
    // (e.g. email/password) — there's nothing to disconnect, so swallow it
    // rather than letting it abort the sign-out below. Bounded as well as
    // caught: on a bad connection it can stall indefinitely, which no catch
    // would rescue.
    try {
      await GoogleSignIn().disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  await FirebaseAuth.instance.signOut();
}

/// [signOutAndCleanup] plus the jump back to [WelcomeScreen], for the logout
/// entry points that sit above AuthGate (the shells' nav menus, HomeScreen's
/// confirm dialog, GigWorkerScreen).
///
/// Navigating to [WelcomeScreen] tears down every route above it (including
/// AuthGate), so the app looks fully logged out the moment that happens — if
/// it ran before [FirebaseAuth.signOut] actually completed and the app got
/// killed right then, Firebase's persisted native session would survive
/// untouched and silently restore the same account on the next launch. So the
/// whole chain is awaited first, and nothing ever looks logged out before it
/// truly is.
Future<void> performSignOut(BuildContext context) async {
  // Read before the first await — the widget may be gone by the time the
  // chain finishes.
  final currentUser = context.read<CurrentUserProvider>();

  await signOutAndCleanup(currentUser, revokeGoogle: true);

  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );
}
