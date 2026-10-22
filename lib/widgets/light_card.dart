import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// White rounded card used on the light Home screen
/// (rooms, services, stats, info cards). Style lives in AppDecor.lightCard.
class LightCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double? width;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const LightCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 16,
    this.width,
    this.borderColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: width,
        padding: padding,
        decoration: AppDecor.lightCard(radius: radius, borderColor: borderColor),
        child: child,
      ),
    );
  }
}