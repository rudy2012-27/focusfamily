import 'package:flutter/services.dart';

/// Talks to the Android (Kotlin) enforcement code.
class NativeBridge {
  static const MethodChannel _ch = MethodChannel('focusfamily/native');

  static Future<Map<String, bool>> permissions() async {
    try {
      final r = await _ch.invokeMethod<Map>('permissions');
      return (r ?? {}).map((k, v) => MapEntry(k.toString(), v == true));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _call(String method, [dynamic args]) async {
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {}
  }

  static Future<void> openUsageAccess() => _call('openUsageAccess');
  static Future<void> openAccessibility() => _call('openAccessibility');
  static Future<void> openBattery() => _call('openBattery');
  static Future<void> requestNotifications() => _call('requestNotifications');

  static Future<bool> requestVpn() async {
    try {
      return (await _ch.invokeMethod<bool>('requestVpn')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startGuard({
    required String childUid,
    required String parentUid,
    required String childName,
  }) =>
      _call('startGuard', {
        'childUid': childUid,
        'parentUid': parentUid,
        'childName': childName,
      });

  static Future<void> stopGuard() => _call('stopGuard');
}
