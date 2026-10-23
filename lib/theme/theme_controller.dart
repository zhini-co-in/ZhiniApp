import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current mode (light / dark) and remembers it between app runs.
class ThemeController {
  ThemeController._();

  static const String _key = 'dark_mode';

  /// true = dark (old navy theme), false = light (new Home theme).
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get isDark => notifier.value;

  /// Call once in main() BEFORE runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notifier.value = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> setDark(bool value) async {
    notifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}