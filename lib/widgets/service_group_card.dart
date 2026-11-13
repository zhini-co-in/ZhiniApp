import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Rounded card like the design: icon + badge, title, subtitle, footer row.
class ServiceGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool light; // true on Home tab (light theme), false on Devices tab
  final VoidCallback onTap;

  const ServiceGroupCard({
    super.key,
    required this.group,
    required this.onTap,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = group['color'] as Color;
    final count = (group['items'] as List).length;

    final bg = AppColors.cardBg;
final border = AppColors.borderSubtle;
final titleColor = AppColors.textPrimary;
final subColor = AppColors.textSecondary;
final linkColor = AppColors.primary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(group['icon'] as IconData, color: color, size: 22),
              ),
              const SizedBox(height: 14),

              // Title: up to 2 lines so "Smartphones & Tablets" is not cut.
              Text(group['title'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: titleColor, fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),

              // Subtitle: up to 2 lines.
              Text(group['sub'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subColor, fontSize: 11.5)),
              const SizedBox(height: 10),
              Divider(height: 1, color: border),
              const SizedBox(height: 10),

              // Footer: text shrinks to fit, so it never overflows on Large font.
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('$count appliances',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                              color: linkColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: subColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2-column grid of ServiceGroupCard (no scrolling of its own).
class ServiceGroupGrid extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  final bool light;
  final void Function(Map<String, dynamic>) onTap;

  const ServiceGroupGrid({
    super.key,
    required this.groups,
    required this.onTap,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < groups.length; i += 2) {
      final a = groups[i];
      final b = i + 1 < groups.length ? groups[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + 2 < groups.length ? 12 : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: ServiceGroupCard(group: a, light: light, onTap: () => onTap(a))),
              const SizedBox(width: 12),
              Expanded(
                child: b == null
                    ? const SizedBox.shrink()
                    : ServiceGroupCard(group: b, light: light, onTap: () => onTap(b)),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}