import 'package:flutter/material.dart';
import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

class WarrantyBadge extends StatelessWidget {
  final DateTime? expiry;
  const WarrantyBadge({super.key, required this.expiry});

  static String _fmt(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    // No warranty -> only red words, no box / icon.
    if (expiry == null) {
      return Text(
        AppStrings.noWarranty,
        style: TextStyle(color: AppColors.danger, fontSize: 10.5, fontWeight: FontWeight.w700),
      );
    }

    final now = DateTime.now();
    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (expiry!.isAfter(now)) {
      color = AppColors.lightSuccess;
      icon = Icons.verified_user_rounded;
      title = AppStrings.warrantyActive;
      subtitle = AppStrings.validTill(_fmt(expiry!));
    } else {
      color = AppColors.danger;
      icon = Icons.error_rounded;
      title = AppStrings.warrantyExpired;
      subtitle = AppStrings.expiredOn(_fmt(expiry!));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
              Text(subtitle, style: TextStyle(color: AppColors.lightTextMuted, fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }
}