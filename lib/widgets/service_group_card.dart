import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_type.dart';

/// Rounded card: icon + badge, title, subtitle.
/// compact = false (Devices tab): icon border + footer row ("6 appliances >")
/// compact = true  (Home tab)   : only icon, title, subtitle
class ServiceGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool light; // true on Home tab (light theme), false on Devices tab
  final bool compact;
  final VoidCallback onTap;

  const ServiceGroupCard({
    super.key,
    required this.group,
    required this.onTap,
    this.light = false,
    this.compact = false,
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md), // 16
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 40 : 48,
                height: compact ? 40 : 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  // Devices tab: border irukku, Home tab (compact): illa
                  border: compact
                      ? null
                      : Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(group['icon'] as IconData,
                    color: color, size: compact ? 20 : 24),
              ),
              const SizedBox(height: AppSpace.gap), // 12

              // Title: up to 2 lines so "Smartphones & Tablets" is not cut.
              Text(group['title'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.cardTitle.copyWith(color: titleColor)),
              const SizedBox(height: AppSpace.xs), // 4

              // Subtitle: up to 2 lines.
              Text(group['sub'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: subColor)),

              // Footer: Devices tab-la mattum
              if (!compact) ...[
                const SizedBox(height: AppSpace.gap),
                Divider(height: 1, color: border),
                const SizedBox(height: AppSpace.gap),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('$count appliances',
                            maxLines: 1,
                            softWrap: false,
                            style: AppType.cardTitle.copyWith(color: linkColor)),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
                  ],
                ),
              ],
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
  final bool compact;
  final void Function(Map<String, dynamic>) onTap;

  const ServiceGroupGrid({
    super.key,
    required this.groups,
    required this.onTap,
    this.light = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < groups.length; i += 2) {
      final a = groups[i];
      final b = i + 1 < groups.length ? groups[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + 2 < groups.length ? AppSpace.gap : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: ServiceGroupCard(
                      group: a, light: light, compact: compact, onTap: () => onTap(a))),
              const SizedBox(width: AppSpace.gap),
              Expanded(
                child: b == null
                    ? const SizedBox.shrink()
                    : ServiceGroupCard(
                        group: b, light: light, compact: compact, onTap: () => onTap(b)),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}
