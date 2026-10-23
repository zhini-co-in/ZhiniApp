import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// "Appearance:  [ Light | Dark ]" row. Drop it anywhere in the Profile tab:
///   const ThemeModeToggle(),
class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.notifier,
      builder: (context, isDark, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: AppDecor.flatCard(radius: 14),
          child: Row(
            children: [
              Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Appearance', style: AppText.cardTitle),
              ),
              _chip('Light', Icons.light_mode_rounded, !isDark, () => ThemeController.setDark(false)),
              const SizedBox(width: 8),
              _chip('Dark', Icons.dark_mode_rounded, isDark, () => ThemeController.setDark(true)),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: selected ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.borderMuted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? AppColors.onPrimary : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.onPrimary : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}