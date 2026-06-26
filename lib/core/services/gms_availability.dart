import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_api_availability/google_api_availability.dart';

class GmsAvailability {
  static bool? _cached;

  /// Returns the cached value synchronously (defaults to false if not yet resolved).
  static bool get cachedIsAvailable => _cached ?? false;

  static Future<bool> get isAvailable async {
    if (_cached != null) return _cached!;
    if (kIsWeb || !Platform.isAndroid) return _cached = true;
    try {
      // Huawei/Honor devices lack real GMS; their HMS compatibility layer can
      // report GMS as available even though Google Maps won't render correctly.
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
        return _cached = false;
      }
      final result = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability();
      _cached = result == GooglePlayServicesAvailability.success;
    } catch (_) {
      _cached = false;
    }
    return _cached!;
  }
}
