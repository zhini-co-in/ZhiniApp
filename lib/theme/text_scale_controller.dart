import 'package:flutter/foundation.dart';

enum FontSizeOption { small, normal, large }

class TextScaleController {
  // Always Default la start aagum
  static final ValueNotifier<FontSizeOption> notifier =
      ValueNotifier(FontSizeOption.normal);

  static double scaleOf(FontSizeOption o) {
    switch (o) {
      case FontSizeOption.small:
        return 1.0;
      case FontSizeOption.normal:
        return 1.16;
      case FontSizeOption.large:
        return 1.3;
    }
  }

  static void set(FontSizeOption o) => notifier.value = o;
}