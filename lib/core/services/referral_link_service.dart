import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Carries a referral code from a shared invite link into the sign-up forms.
///
/// Invite links look like `https://go.giggre.com/r/GX82KL19` (see
/// [linkFor]). The landing page behind that URL (hosting/invite.html) sends
/// the visitor to the right store; the code then reaches the app by one of:
///  - App Links / Universal Links, when the app is already installed — the
///    tap opens the app directly and app_links delivers the URL.
///  - Android new installs: the landing page passes `referrer=ref=<code>` to
///    the Play Store, which hands it back through the Install Referrer API on
///    first launch.
///  - iOS new installs: the App Store passes nothing through, so the landing
///    page copies the invite link to the clipboard and [checkClipboardOnce]
///    reads it the first time a sign-up form opens (iOS shows "Allow Paste").
///
/// Whichever arrives is held in [pendingCode] (persisted, so it survives the
/// app being killed between install and sign-up) until the user reaches the
/// signed-in app, where AuthGate calls [clear].
class ReferralLinkService {
  ReferralLinkService._();
  static final ReferralLinkService instance = ReferralLinkService._();

  static const String linkHost = 'go.giggre.com';

  static String linkFor(String code) => 'https://$linkHost/r/$code';

  static const _prefsCodeKey = 'referral_link_pending_code';
  static const _prefsSavedAtKey = 'referral_link_pending_saved_at';
  // Install-begin timestamp of the install whose referrer was last read. A
  // plain "checked" flag isn't enough: Android Auto Backup restores
  // SharedPreferences on reinstall, so the flag from a previous install
  // would skip the new install's referrer.
  static const _prefsReferrerInstallKey = 'referral_link_install_referrer_install_ts';
  static const _prefsClipboardCheckedKey = 'referral_link_clipboard_checked';

  // A stale code from a link tapped weeks ago shouldn't silently credit that
  // referrer on an unrelated later sign-up.
  static const _maxAge = Duration(days: 30);

  // Same shape register_screen.dart's _generateReferralCode produces. Used
  // only for free text (clipboard, old QR codes) so arbitrary copied words
  // never land in the field; links on our own host are trusted by path.
  static final _codePattern = RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z]{2}[0-9]{2}$');
  static final _linkCodePattern = RegExp(r'^[A-Za-z0-9]{8}$');
  // An invite link anywhere in longer text — e.g. a friend copying the whole
  // share message rather than just the link.
  static final _embeddedLinkPattern = RegExp(
    r'https://go\.giggre\.com/r/([A-Za-z0-9]{8})(?![A-Za-z0-9])',
  );

  final ValueNotifier<String?> pendingCode = ValueNotifier<String?>(null);
  StreamSubscription<Uri>? _linkSubscription;

  /// Extracts a referral code from an invite link on [linkHost] or from a
  /// bare code (what QR codes contained before invite links existed).
  static String? parseCode(String raw) {
    final text = raw.trim();
    final bare = text.toUpperCase();
    if (_codePattern.hasMatch(bare)) return bare;

    final uri = Uri.tryParse(text);
    if (uri != null && uri.host == linkHost) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          segments[0] == 'r' &&
          _linkCodePattern.hasMatch(segments[1])) {
        return segments[1].toUpperCase();
      }
      return null;
    }

    return _embeddedLinkPattern.firstMatch(text)?.group(1)?.toUpperCase();
  }

  // Call once at app startup (see main.dart). Only the saved-code read is
  // awaited; link listening and the install-referrer lookup run in the
  // background so they never delay the first frame.
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsCodeKey);
      final savedAt = prefs.getInt(_prefsSavedAtKey);
      if (saved != null && savedAt != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(savedAt),
        );
        if (age < _maxAge) {
          pendingCode.value = saved;
        } else {
          await clear();
        }
      }
    } catch (e) {
      debugPrint('[ReferralLink] failed to load saved code: $e');
    }

    _listenForLinks();
    if (Platform.isAndroid) unawaited(_checkInstallReferrerOnce());
  }

  void _listenForLinks() {
    final appLinks = AppLinks();
    _linkSubscription ??= appLinks.uriLinkStream.listen(
      (uri) => _offer(uri.toString()),
      onError: (Object e) => debugPrint('[ReferralLink] link error: $e'),
    );
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _offer(uri.toString());
    }).catchError((Object e) {
      debugPrint('[ReferralLink] initial link error: $e');
    });
  }

  Future<void> _checkInstallReferrerOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final details = await PlayInstallReferrer.installReferrer;
      final installTs = details.installBeginTimestampSeconds;
      if (prefs.getInt(_prefsReferrerInstallKey) == installTs) return;
      await prefs.setInt(_prefsReferrerInstallKey, installTs);
      // Organic installs report e.g. "utm_source=google-play&utm_medium=organic".
      final referrer = details.installReferrer;
      debugPrint('[ReferralLink] install referrer: $referrer');
      if (referrer == null || referrer.isEmpty) return;
      final ref = Uri.splitQueryString(referrer)['ref'];
      if (ref != null) _offer(ref);
    } catch (e) {
      // Not installed from Play (sideload, emulator, dev flavor) — nothing to read.
      debugPrint('[ReferralLink] install referrer unavailable: $e');
    }
  }

  /// iOS only, at most once per install: reads an invite link the landing
  /// page copied to the clipboard. Call when a sign-up form opens — reading
  /// triggers iOS's "Allow Paste" prompt, which makes sense there and not
  /// on a cold start.
  Future<void> checkClipboardOnce() async {
    if (kIsWeb || !Platform.isIOS || pendingCode.value != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsClipboardCheckedKey) == true) return;
      // hasStrings doesn't prompt, so an empty clipboard never shows the
      // dialog — and doesn't use up the one check either.
      if (!await Clipboard.hasStrings()) return;
      await prefs.setBool(_prefsClipboardCheckedKey, true);
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null) _offer(text);
    } catch (e) {
      debugPrint('[ReferralLink] clipboard check failed: $e');
    }
  }

  void _offer(String raw) {
    final code = parseCode(raw);
    if (code == null) return;
    pendingCode.value = code;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefsCodeKey, code);
      prefs.setInt(_prefsSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    });
  }

  /// Fills [controller] with the pending code now if it's empty, and again
  /// whenever a code arrives later (e.g. the clipboard read finishing, or a
  /// link tapped while the form is open). Never overwrites what the user
  /// typed. Returns the listener remover — call it from dispose().
  VoidCallback bindField(TextEditingController controller) {
    void fill() {
      final code = pendingCode.value;
      if (code != null && controller.text.trim().isEmpty) {
        controller.text = code;
      }
    }

    fill();
    pendingCode.addListener(fill);
    return () => pendingCode.removeListener(fill);
  }

  Future<void> clear() async {
    pendingCode.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsCodeKey);
      await prefs.remove(_prefsSavedAtKey);
    } catch (_) {}
  }
}
