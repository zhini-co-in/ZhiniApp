import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// "Devices                      View all >"
/// Pass [onManage] to show the right-side link; omit it (or pass null) to hide the link.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onManage;

  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel = 'Manage',
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final showAction = onManage != null && actionLabel != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppText.lightSectionTitle),
        if (showAction)
          GestureDetector(
            onTap: onManage,
            child: Row(
              children: [
                Text(actionLabel!, style: AppText.lightLink),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.lightPrimary, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}