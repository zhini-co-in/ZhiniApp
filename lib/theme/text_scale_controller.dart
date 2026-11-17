import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FontSizeOption { small, normal, large }

class TextScaleController {
  static const _key = 'font_size_option';

  // First install -> Small
  static final ValueNotifier<FontSizeOption> notifier =
      ValueNotifier(FontSizeOption.small);

  static double scaleOf(FontSizeOption o) {
    switch (o) {
      case FontSizeOption.small:
        return 1.0;
      case FontSizeOption.normal: // UI-la "Medium"
        return 1.16;
      case FontSizeOption.large:
        return 1.3;
    }
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      notifier.value = FontSizeOption.values.firstWhere(
        (o) => o.name == saved,
        orElse: () => FontSizeOption.small,
      );
    } catch (e) {
      debugPrint('TextScale init error: $e');
    }
  }

  static void set(FontSizeOption o) {
    notifier.value = o;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, o.name))
        .catchError((e) => debugPrint('TextScale save error: $e'));
  }
}