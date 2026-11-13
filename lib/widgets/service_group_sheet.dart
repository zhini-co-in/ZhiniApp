import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

IconData serviceItemIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('mobile') || n.contains('phone')) return Icons.smartphone_rounded;
  if (n.contains('tablet')) return Icons.tablet_mac_rounded;
  if (n.contains('watch')) return Icons.watch_rounded;
  if (n.contains('headphone')) return Icons.headphones_rounded;
  if (n.contains('speaker')) return Icons.speaker_rounded;
  if (n.contains('laptop')) return Icons.laptop_mac_rounded;
  if (n.contains('printer')) return Icons.print_rounded;
  if (n.contains('router')) return Icons.router_rounded;
  if (n.contains('projector')) return Icons.videocam_rounded;
  if (n.contains('ups') || n.contains('inverter')) return Icons.battery_charging_full_rounded;
  if (n.contains('fridge')) return Icons.kitchen_rounded;
  if (n.contains('microwave') || n.contains('otg')) return Icons.microwave_rounded;
  if (n.contains('chimney')) return Icons.air_rounded;
  if (n.contains('mixer') || n.contains('juicer') || n.contains('grinder') || n.contains('processor')) {
    return Icons.blender_rounded;
  }
  if (n.contains('stove')) return Icons.local_fire_department_rounded;
  if (n.contains('dishwasher')) return Icons.countertops_rounded;
  if (n.contains('rice')) return Icons.rice_bowl_rounded;
  if (n.contains('kettle')) return Icons.coffee_maker_rounded;
  if (n.contains('toaster')) return Icons.bakery_dining_rounded;
  if (n.contains('tv') || n.contains('home theatre')) return Icons.tv_rounded;
  if (n.contains('air conditioner')) return Icons.ac_unit_rounded;
  if (n.contains('fan')) return Icons.mode_fan_off_rounded;
  if (n.contains('cooler')) return Icons.air_rounded;
  if (n.contains('geyser') || n.contains('heater')) return Icons.hot_tub_rounded;
  if (n.contains('purifier')) return Icons.water_drop_rounded;
  if (n.contains('washing')) return Icons.local_laundry_service_rounded;
  if (n.contains('vacuum')) return Icons.cleaning_services_rounded;
  if (n.contains('iron')) return Icons.iron_rounded;
  return Icons.devices_other_rounded;
}

void showServiceGroupSheet(
  BuildContext context, {
  required Map<String, dynamic> group,
  required void Function(String name) onSelect,
  required VoidCallback onScan,
}) {
  final color = group['color'] as Color;
  final items = (group['items'] as List).cast<String>();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) {
      return SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.72,
        child: Column(
          children: [
            // ── Gradient header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.0)],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, color.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(group['icon'] as IconData, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(group['title'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(group['sub'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${items.length} appliances  •  Doorstep repair',
                          style: TextStyle(
                              color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Items grid ──
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 72,
                ),
                itemBuilder: (_, i) {
                  final name = items[i];
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 250 + (i * 40).clamp(0, 400)),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
                    ),
                    child: Material(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onSelect(name);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: color.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(serviceItemIcon(name), color: color, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2)),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  size: 18, color: AppColors.textMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Scan button ──
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onScan();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: Icon(Icons.qr_code_scanner_rounded,
                        size: 20, color: AppColors.onPrimary),
                    label: Text('Scan to add product',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}