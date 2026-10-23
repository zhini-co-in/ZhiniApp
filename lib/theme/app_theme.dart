import 'package:flutter/material.dart';
import 'theme_controller.dart';
import 'dart:ui' show ColorSpace;

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

/// A color that holds a LIGHT and a DARK value and picks one at paint time.
/// It is `const`-friendly, so `const Text(style: AppText.x)` keeps working.
class DynColor extends Color {
  const DynColor(this.light, this.dark) : super(0);

  final Color light;
  final Color dark;

  Color get _c => ThemeController.isDark ? dark : light;

  @override
  double get a => _c.a;
  @override
  double get r => _c.r;
  @override
  double get g => _c.g;
  @override
  double get b => _c.b;
  @override
  ColorSpace get colorSpace => _c.colorSpace;
}

class AppColors {
  AppColors._();

  // Each color = DynColor(LIGHT value, DARK value).
  // Edit a value here -> that color changes in the whole app.

  // Backgrounds
  static const Color scaffoldBg = DynColor(Color(0xFFF5F8FF), Color(0xFF0A1628));
  static const Color cardBg = DynColor(Color(0xFFFFFFFF), Color(0xFF0F2038));
  static const Color cardBgAlt = DynColor(Color(0xFFEEF3FC), Color(0xFF16294A));
  static const Color memberAvatarBg = DynColor(Color(0xFFDCE8FF), Color(0xFF1E3A8A));

  // Brand / accents
  static const Color primary = DynColor(Color(0xFF2B7BFF), Color(0xFF2196F3));
  static const Color primaryBorder = DynColor(Color(0xFF8FBAFF), Color(0xFF64B5F6));
  static const Color primarySoft = DynColor(Color(0x262B7BFF), Color(0x262196F3));
  static const Color primaryFaint = DynColor(Color(0x0D2B7BFF), Color(0x0D2196F3));
  static const Color onPrimary = Colors.white; // text/icons ON a blue button

  // Status colors
  static const Color success = DynColor(Color(0xFF22C55E), Color(0xFF69F0AE));
  static const Color warning = DynColor(Color(0xFFF59E0B), Color(0xFFFFAB40));
  static const Color danger = DynColor(Color(0xFFEF4444), Color(0xFFFF5252));
  static const Color star = Colors.amber;

  // Text
  static const Color textPrimary = DynColor(Color(0xFF0F1C3F), Color(0xFFFFFFFF));
  static const Color textSecondary = DynColor(Color(0xFF4A5A7A), Color(0xB3FFFFFF));
  static const Color textMuted = DynColor(Color(0xFF7A8BA8), Color(0x8AFFFFFF));
  static const Color textFaint = DynColor(Color(0xFF9AA5B5), Color(0x62FFFFFF));
  static const Color textDisabled = DynColor(Color(0xFFB0BACE), Color(0x3DFFFFFF));
  static const Color borderSubtle = DynColor(Color(0xFFE8EEF8), Color(0x1AFFFFFF));
  static const Color borderMuted = DynColor(Color(0xFFE0E7F5), Color(0x3DFFFFFF));

  // Home-screen names (same palette, kept so home_tab.dart needs no change)
  static const Color lightBg = scaffoldBg;
  static const Color lightSurface = cardBg;
  static const Color lightPrimary = primary;
  static const Color lightSuccess = success;
  static const Color lightWarning = warning;
  static const Color lightPurple = DynColor(Color(0xFF8B5CF6), Color(0xFFA78BFA));
  static const Color lightTextDark = textPrimary;
  static const Color lightTextBody = DynColor(Color(0xFF3D4F6F), Color(0xB3FFFFFF));
  static const Color lightTextSoft = textSecondary;
  static const Color lightTextMuted = textMuted;
  static const Color lightHint = textFaint;
  static const Color lightChevron = textDisabled;
  static const Color lightBorder = borderSubtle;
  static const Color lightBorderStrong = borderMuted;

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
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

static ButtonStyle get primaryOutlinedButton => OutlinedButton.styleFrom(
      side: const BorderSide(color: AppColors.primary),
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

  // ───────────── LIGHT ─────────────

  static LinearGradient get lightHeaderGradient => ThemeController.isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16406B), Color(0xFF0F2347), Color(0xFF0A1628)],
          stops: [0.0, 0.55, 1.0],
        )
      : const LinearGradient(
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