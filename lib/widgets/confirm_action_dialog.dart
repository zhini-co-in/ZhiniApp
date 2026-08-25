import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Standard "Remove X?" / "Log out?" confirm dialog used throughout the app.
/// Returns true if confirmed. Styling comes from AppDecor/AppColors/AppText.
Future<bool?> showConfirmActionDialog(
  BuildContext context, {
  required String title,
  required String content,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Remove',
  Color confirmColor = AppColors.danger,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.dialogShape,
      title: Text(title, style: AppText.dialogTitle),
      content: Text(content, style: AppText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel, style: const TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
        ),
      ],
    ),
  );
}