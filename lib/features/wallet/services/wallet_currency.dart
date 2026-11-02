import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';

/// The Gig Wallet's own currency — what the balance, history and every
/// amount in Top Up / Send / Withdraw are in.
///
/// Matches the server (walletCurrency in functions/src/gigPointsRequests.ts):
/// wallets/{uid}.currencyCode, else the user's location currency, else USD.
/// The server checks amounts and limits in this currency, so the app must
/// show and enter them in it too — the user's *location* currency can differ
/// (e.g. a PHP wallet while the phone is abroad).
///
/// WalletScreen keeps this in sync from wallets/{uid}; screens opened from it
/// read it with [WalletCurrency.of].
class WalletCurrency {
  WalletCurrency._();

  static final Map<String, String> _byUid = {};

  static void set(String uid, String? code) {
    if (code != null && code.trim().isNotEmpty) _byUid[uid] = code.trim();
  }

  /// The signed-in user's wallet currency, else their location currency.
  static String of(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return (uid == null ? null : _byUid[uid]) ??
        context.read<CurrentUserProvider>().currencyCode;
  }
}
