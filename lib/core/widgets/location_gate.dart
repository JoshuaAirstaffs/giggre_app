// Blocks the app while the user is signed in but location is unavailable.
//
// Gigs are matched, shown, and checked in by location, so the app can't be
// used without it. Covers every screen (it sits in MaterialApp.builder, above
// the navigator and the Gab bubble) until location services are on and the
// app has location permission. Rechecks when the service is toggled and when
// the app comes back from Settings.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/welcome_screen.dart';
import '../providers/current_user_provider.dart';
import '../services/sign_out_service.dart';
import '../theme/app_colors.dart';

enum _LocationState { checking, ok, serviceOff, denied, deniedForever }

class LocationGate extends StatefulWidget {
  const LocationGate({super.key, required this.navigatorKey});

  /// Needed to leave the gate by logging out: it sits above the navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  _LocationState _state = _LocationState.checking;
  StreamSubscription<ServiceStatus>? _serviceSub;
  bool _busy = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (!_supported) {
      _state = _LocationState.ok;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _serviceSub = Geolocator.getServiceStatusStream().listen((_) => _check());
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceSub?.cancel();
    super.dispose();
  }

  // Back from Settings (or the permission prompt): see what changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final _LocationState next;
    if (!await Geolocator.isLocationServiceEnabled()) {
      next = _LocationState.serviceOff;
    } else {
      next = switch (await Geolocator.checkPermission()) {
        LocationPermission.always ||
        LocationPermission.whileInUse => _LocationState.ok,
        LocationPermission.deniedForever => _LocationState.deniedForever,
        _ => _LocationState.denied,
      };
    }
    if (mounted && next != _state) setState(() => _state = next);
  }

  Future<void> _fix() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (_state) {
        case _LocationState.serviceOff:
          await Geolocator.openLocationSettings();
        case _LocationState.denied:
          await Geolocator.requestPermission();
        case _LocationState.deniedForever:
          await Geolocator.openAppSettings();
        case _LocationState.checking:
        case _LocationState.ok:
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _check();
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    await signOutAndCleanup(
      context.read<CurrentUserProvider>(),
      revokeGoogle: true,
    );
    widget.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<CurrentUserProvider, bool>(
      (p) => p.isLoggedIn,
    );
    if (!signedIn ||
        _state == _LocationState.ok ||
        _state == _LocationState.checking) {
      return const SizedBox.shrink();
    }

    final (title, message, action) = switch (_state) {
      _LocationState.serviceOff => (
        'Turn on location',
        'Giggre needs your location to show gigs near you, match you with '
            'workers or hosts, and confirm check-ins. Turn on location '
            'services to continue.',
        'Turn on location',
      ),
      _LocationState.deniedForever => (
        'Allow location access',
        'Location access for Giggre is turned off. Open Settings, tap '
            'Location, and allow Giggre to use your location to continue.',
        'Open Settings',
      ),
      _ => (
        'Allow location access',
        'Giggre needs your location to show gigs near you, match you with '
            'workers or hosts, and confirm check-ins. Allow location access '
            'to continue.',
        'Allow location',
      ),
    };

    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_off_rounded,
                        color: kBlue,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: kSub,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _fix,
                        style: FilledButton.styleFrom(
                          backgroundColor: kBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          action,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _logout,
                      child: const Text(
                        'Log out',
                        style: TextStyle(color: kSub, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
