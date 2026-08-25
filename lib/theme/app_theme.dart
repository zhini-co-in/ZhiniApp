import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------
/// APP THEME — the "CSS" of the app.
///
/// Every color, text style, and reusable decoration lives here instead of
/// being hardcoded inside individual widgets/dialogs. Widgets should
/// reference `AppColors.*`, `AppText.*`, `AppDecor.*` instead of literal
/// Color(0x...) / TextStyle(...) values, the same way you'd reference CSS
/// classes/variables instead of inline styles.
/// ---------------------------------------------------------------------

class AppColors {
  AppColors._();

  // Backgrounds
  static const Color scaffoldBg = Color(0xFF0A1628);
  static const Color cardBg = Color(0xFF0F2038);
  static const Color cardBgAlt = Color(0xFF16294A);
  static const Color memberAvatarBg = Color(0xFF1E3A8A);

  // Brand / accents
  static const Color primary = Colors.blue;
  static Color primaryBorder = Colors.blue.shade300;
  static Color primarySoft = Colors.blue.withValues(alpha: 0.15);
  static Color primaryFaint = Colors.blue.withValues(alpha: 0.05);

  // Status colors
  static const Color success = Colors.greenAccent;
  static const Color warning = Colors.orangeAccent;
  static const Color danger = Colors.redAccent;
  static const Color star = Colors.amber;

  // Text
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textMuted = Colors.white54;
  static const Color textFaint = Colors.white38;
  static const Color textDisabled = Colors.white24;
  static const Color borderSubtle = Colors.white10;
  static const Color borderMuted = Colors.white24;

  // Card border by warranty/alert status
  static Color statusColor(String status) {
    switch (status) {
      case 'danger':
      case 'expired':
        return danger;
      case 'warning':
      case 'expiring':
        return warning;
      case 'active':
        return success;
      default:
        return textFaint;
    }
  }
}

class AppText {
  AppText._();

  static const TextStyle sectionHeader = TextStyle(
    color: Colors.blue,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static const TextStyle dialogTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle cardTitle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  static const TextStyle body = TextStyle(color: AppColors.textSecondary, fontSize: 13);
  static const TextStyle caption = TextStyle(color: AppColors.textMuted, fontSize: 12);
  static const TextStyle faintCaption = TextStyle(color: AppColors.textFaint, fontSize: 11);

  static const TextStyle fieldHint = TextStyle(color: AppColors.textFaint);

  static const TextStyle chipSelected = TextStyle(color: AppColors.textPrimary, fontSize: 12);
  static const TextStyle chipUnselected = TextStyle(color: AppColors.textSecondary, fontSize: 12);

  static const TextStyle button = TextStyle(color: AppColors.textPrimary, fontSize: 16);
  static const TextStyle linkAction = TextStyle(color: Colors.blue, fontSize: 12);
}

class AppDecor {
  AppDecor._();

  /// Standard rounded dialog shape (16px), used by every AlertDialog.
  static RoundedRectangleBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  /// Standard bottom-sheet shape (rounded top corners).
  static const RoundedRectangleBorder sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  );

  /// The blue-bordered translucent card used for service-provider cards,
  /// add-option tiles, etc.
  static BoxDecoration outlinedCard({double radius = 10}) => BoxDecoration(
        color: AppColors.primaryFaint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.4)),
      );

  /// The flat dark card used for room tiles / stat boxes, with an optional
  /// status-colored border.
  static BoxDecoration flatCard({Color borderColor = AppColors.borderSubtle, double radius = 16}) =>
      BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      );

  static InputBorder fieldBorder({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: focused
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide(color: AppColors.primaryBorder),
      );

  static InputDecoration textFieldDecoration(String hint, {int? maxLength}) => InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: AppText.fieldHint,
        enabledBorder: fieldBorder(),
        focusedBorder: fieldBorder(focused: true),
      );
}