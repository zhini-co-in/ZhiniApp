import 'dart:io';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  static Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) return;

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        // Force update (full screen, skip panna mudiyathu)
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      // Debug build / side-load na error varum, ignore pannalam
      print('Update check failed: $e');
    }
  }
}