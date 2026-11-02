import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';

/// "Let others find me" — whether this user appears in user search
/// (users/{uid}.searchable, mirrored to publicProfiles by
/// syncPublicProfile). Missing means on. People they've already worked with
/// can still message them when it's off.
class SearchableSwitch extends StatelessWidget {
  const SearchableSwitch({super.key});

  static DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Future<void> set(bool value) async =>
      _ref?.set({'searchable': value}, SetOptions(merge: true));

  /// For the row's onTap, so the whole row toggles like the theme switch.
  static Future<void> toggle() async {
    final ref = _ref;
    if (ref == null) return;
    final snap = await ref.get();
    await set(snap.data()?['searchable'] == false);
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ref;
    if (ref == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) => Switch(
        value: snap.data?.data()?['searchable'] != false,
        activeThumbColor: kAmber,
        onChanged: set,
      ),
    );
  }
}
