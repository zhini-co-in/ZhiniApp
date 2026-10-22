import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------
/// APP THEME — the "CSS" of the app.
///
/// Every color, text style, and reusable decoration lives here instead of
/// being hardcoded inside individual widgets/dialogs. Change a value here
/// and every screen that uses it changes.
///
///  * Dark palette  -> dialogs, sheets, room detail, etc.
///  * Light palette -> new Home screen (names start with `light`)
/// ---------------------------------------------------------------------

class AppColors {
  AppColors._();

  // ───────────── MAIN PALETTE (used by ALL screens) ─────────────
  // Every screen/dialog/sheet that uses these names now follows the
  // light Home look. Change a value here -> whole app changes.

  // Backgrounds
  static const Color scaffoldBg = Color(0xFFF5F8FF);
  static const Color cardBg = Colors.white;
  static const Color cardBgAlt = Color(0xFFEEF3FC);
  static const Color memberAvatarBg = Color(0xFFDCE8FF);

  // Brand / accents
  static const Color primary = Color(0xFF2B7BFF);
  static const Color primaryBorder = Color(0xFF8FBAFF);
  static const Color primarySoft = Color(0x262B7BFF); // 15%
  static const Color primaryFaint = Color(0x0D2B7BFF); // 5%
  static const Color onPrimary = Colors.white; // text/icons ON a blue button

  // Status colors
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color star = Colors.amber;

  // Text
  static const Color textPrimary = Color(0xFF0F1C3F);
  static const Color textSecondary = Color(0xFF4A5A7A);
  static const Color textMuted = Color(0xFF7A8BA8);
  static const Color textFaint = Color(0xFF9AA5B5);
  static const Color textDisabled = Color(0xFFB0BACE);
  static const Color borderSubtle = Color(0xFFE8EEF8);
  static const Color borderMuted = Color(0xFFE0E7F5);

  // ───────────── LIGHT THEME (Home screen) ─────────────
  static const Color lightBg = scaffoldBg;
  static const Color lightSurface = Colors.white;
  static const Color lightPrimary = Color(0xFF2B7BFF);
  static const Color lightSuccess = Color(0xFF22C55E);
  static const Color lightPurple = Color(0xFF8B5CF6);
  static const Color lightWarning = Color(0xFFF59E0B);

  static const Color lightTextDark = Color(0xFF0F1C3F);
  static const Color lightTextBody = Color(0xFF3D4F6F);
  static const Color lightTextSoft = Color(0xFF4A5A7A);
  static const Color lightTextMuted = Color(0xFF7A8BA8);
  static const Color lightHint = Color(0xFF9AA5B5);
  static const Color lightChevron = Color(0xFFB0BACE);

  static const Color lightBorder = Color(0xFFE8EEF8);
  static const Color lightBorderStrong = Color(0xFFE0E7F5);

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

  // ───────────── DARK ─────────────
  static const TextStyle sectionHeader = TextStyle(
    color: AppColors.primary,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  /// Small uppercase label, e.g. "ROOM NAME", "COMMON ROOMS".
  static const TextStyle label = TextStyle(
    color: AppColors.primary,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );
  static const TextStyle labelMuted = TextStyle(
    color: AppColors.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
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

  static const TextStyle button = TextStyle(color: AppColors.onPrimary, fontSize: 16);
  static const TextStyle linkAction = TextStyle(color: AppColors.primary, fontSize: 12);
  static const TextStyle cancelAction = TextStyle(color: AppColors.textMuted);

  // ───────────── LIGHT ─────────────
  static const TextStyle lightSectionTitle = TextStyle(
    color: AppColors.lightTextDark,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle lightCardTitle = TextStyle(
    color: AppColors.lightTextDark,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle lightCaption = TextStyle(
    color: AppColors.lightTextMuted,
    fontSize: 11.5,
  );
  static const TextStyle lightLink = TextStyle(
    color: AppColors.lightPrimary,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle lightSuccessCaption = TextStyle(
    color: AppColors.lightSuccess,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle lightHeroTitle = TextStyle(
    color: AppColors.lightTextDark,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );
  static const TextStyle lightHeroSubtitle = TextStyle(
    color: AppColors.lightTextBody,
    fontSize: 13,
    height: 1.35,
  );
}

class AppDecor {
  AppDecor._();

  // ───────────── DARK ─────────────

  /// Standard rounded dialog shape (16px), used by every AlertDialog.
  static RoundedRectangleBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  /// Standard bottom-sheet shape (rounded top corners).
  static const RoundedRectangleBorder sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  );

  /// Blue-bordered translucent card.
  static BoxDecoration outlinedCard({double radius = 10}) => BoxDecoration(
        color: AppColors.primaryFaint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.4)),
      );

  /// Flat dark card, with optional status-colored border.
  static BoxDecoration flatCard({Color borderColor = AppColors.borderSubtle, double radius = 16}) =>
      BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      );

  static InputBorder fieldBorder({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: focused
            ? const BorderSide(color: AppColors.primary, width: 2)
            : BorderSide(color: AppColors.primaryBorder),
      );

  static InputDecoration textFieldDecoration(String hint, {int? maxLength}) => InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: AppText.fieldHint,
        enabledBorder: fieldBorder(),
        focusedBorder: fieldBorder(focused: true),
      );

  /// Full-width blue filled button (dialog "Continue", "Create room"...).
  static ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    padding: const EdgeInsets.symmetric(vertical: 13),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  /// Full-width blue outlined button.
  static ButtonStyle primaryOutlinedButton = OutlinedButton.styleFrom(
    side: const BorderSide(color: AppColors.primary),
    padding: const EdgeInsets.symmetric(vertical: 13),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  // ───────────── LIGHT ─────────────

  static const LinearGradient lightHeaderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF4BA3F0),
      Color(0xFF7EC0F8),
      Color(0xFFB8DFFC),
      Color(0xFFEAF6FF),
      Color(0xFFF5F8FF),
    ],
    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
  );

  /// White card with soft border — rooms, services, stats, info cards.
  static BoxDecoration lightCard({double radius = 16, Color? borderColor}) => BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.lightBorder),
      );

  /// Small tinted square behind an icon.
  static BoxDecoration lightIconBox({Color color = AppColors.lightPrimary, double radius = 10}) =>
      BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
      );
}