import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The standard ZHINI text-field styling used across every add/edit dialog
/// (address, room name, brand, warranty, manual appliance entry, etc).
/// Pulls its look from [AppDecor]/[AppColors] (the app's central
/// "stylesheet") instead of hardcoding colors/borders itself.
class AppDialogField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final bool autofocus;
  final double fontSize;

  const AppDialogField({
    super.key,
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.autofocus = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      autofocus: autofocus,
      style: TextStyle(color: AppColors.textPrimary, fontSize: fontSize),
      decoration: AppDecor.textFieldDecoration(hint, maxLength: maxLength),
    );
  }
}