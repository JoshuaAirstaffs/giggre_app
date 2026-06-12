import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:giggre_app/main.dart' show navigatorKey;
import 'package:giggre_app/core/theme/app_colors.dart';

class AppUpdateChecker extends StatefulWidget {
  final Widget child;
  const AppUpdateChecker({super.key, required this.child});

  @override
  State<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends State<AppUpdateChecker>
    with WidgetsBindingObserver {
  bool _dialogShown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    _timer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _checkForUpdate(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    debugPrint('[AppUpdate] _checkForUpdate called — isWeb:$kIsWeb platform:${kIsWeb ? 'web' : Platform.operatingSystem}');
    if (_dialogShown || kIsWeb || !Platform.isAndroid) return;
    debugPrint('[AppUpdate] Checking for update...');
    try {
      final info = await InAppUpdate.checkForUpdate();
      debugPrint('[AppUpdate] Availability     : ${info.updateAvailability}');
      debugPrint('[AppUpdate] Available version : ${info.availableVersionCode ?? 'n/a'}');
      debugPrint('[AppUpdate] Staleness days    : ${info.clientVersionStalenessDays ?? 'n/a'}');
      debugPrint('[AppUpdate] Immediate allowed : ${info.immediateUpdateAllowed}');
      debugPrint('[AppUpdate] Flexible allowed  : ${info.flexibleUpdateAllowed}');
      debugPrint('[AppUpdate] Install status    : ${info.installStatus}');
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        debugPrint('[AppUpdate] → New version detected, showing modal');
        _dialogShown = true;
        _showUpdateDialog();
      } else {
        debugPrint('[AppUpdate] → No update available');
      }
    } catch (e) {
      debugPrint('[AppUpdate] check error: $e');
    }
  }

  void _showUpdateDialog() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateDialog());
      return;
    }
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(
        onUpdate: () async {
          Navigator.of(ctx, rootNavigator: true).pop();
          try {
            await InAppUpdate.performImmediateUpdate();
          } catch (e) {
            debugPrint('[AppUpdate] update error: $e');
          }
        },
        onLater: () {
          Navigator.of(ctx, rootNavigator: true).pop();
          _dialogShown = false;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  const _UpdateDialog({required this.onUpdate, required this.onLater});

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: kBlue.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.system_update_rounded,
                  color: kBlue,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'New Update Available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A new version of Giggre is available. Update now to get the latest features and bug fixes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSub, fontSize: 13.5, height: 1.6),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onLater,
              child: const Text(
                'Later',
                style: TextStyle(color: kSub, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
