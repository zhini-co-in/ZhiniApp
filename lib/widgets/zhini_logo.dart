import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

/// ZHINI logo. Light mode -> black Z, Dark mode -> original logo.
class ZhiniLogo extends StatelessWidget {
  final double size;
  const ZhiniLogo({super.key, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      ThemeController.isDark
          ? 'assets/Zhini_Icon1.png'
          : 'assets/Zhini_Icon_Light.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}