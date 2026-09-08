import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceIdService {
  static String? _cachedId;

  /// Returns a stable per-device identifier:
  /// - Android: androidId (survives app reinstall, changes on factory reset)
  /// - iOS: identifierForVendor (changes if ALL apps from same vendor removed)
  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    final deviceInfo = DeviceInfoPlugin();
    String id;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id; // androidId
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor ?? 'unknown-ios-device';
    } else {
      id = 'unknown-platform-device';
    }

    _cachedId = id;
    return id;
  }
}