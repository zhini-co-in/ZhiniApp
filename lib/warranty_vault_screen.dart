// lib/warranty_vault_screen.dart
//
// Warranty Vault: appliances of the SELECTED home, grouped by warranty
// status (Active / Expiring soon / Expired / No warranty).
// Data comes from the Hive 'homes' box that HomeTab also uses, so it works
// offline and refreshes whenever the box changes.

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'constants/app_strings.dart';
import 'models/home_model.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/device_details_sheet.dart';

enum _WStatus { active, expiring, expired, none }

class _VaultItem {
  final DeviceEntry entry;
  final String product;
  final String brand;
  final String homeLabel;
  final DateTime? expiry;
  final _WStatus status;

  _VaultItem({
    required this.entry,
    required this.product,
    required this.brand,
    required this.homeLabel,
    required this.expiry,
    required this.status,
  });
}

class WarrantyVaultScreen extends StatefulWidget {
  final String mobileNumber;
  final String name;

  /// Selected home. If null/empty, devices of every home are shown.
  final String? homeId;

  const WarrantyVaultScreen({
    super.key,
    required this.mobileNumber,
    this.name = '',
    this.homeId,
  });

  @override
  State<WarrantyVaultScreen> createState() => _WarrantyVaultScreenState();
}

class _WarrantyVaultScreenState extends State<WarrantyVaultScreen> {
  final _homeBox = Hive.box<HomeModel>('homes');

  // null = All
  _WStatus? _filter;

  static const _hiddenSetupRoomKey = '__setup__';

  bool _isDefaultHome(Map<String, dynamic> home) =>
      (home['address']?.toString().trim().toLowerCase() ?? '') == 'default';

  // ---------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------
  List<_VaultItem> _collect() {
    final out = <_VaultItem>[];
    final now = DateTime.now();

    for (final h in _homeBox.values) {
      final home = h.toMap();
      final homeId = home['id']?.toString();

      // Only the selected home.
      if (widget.homeId != null && widget.homeId!.isNotEmpty && homeId != widget.homeId) {
        continue;
      }

      final address = home['address']?.toString() ?? '';
      final pincode = home['pincode']?.toString() ?? '';
      final isDefault = _isDefaultHome(home);
      final firstPart = address.split(',').first.trim();
      final homeLabel = isDefault ? 'Unassigned' : (firstPart.isNotEmpty ? firstPart : 'Home');

      final rooms = (home['rooms'] as Map?) ?? {};
      rooms.forEach((roomKey, items) {
        if (items is! List) return;
        if (roomKey.toString().toLowerCase() == _hiddenSetupRoomKey) return;

        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final expiry = WarrantyUtils.parseExpiry(
            item['warranty']?.toString(),
            referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
          );

          _WStatus status;
          if (expiry == null) {
            status = _WStatus.none;
          } else if (!expiry.isAfter(now)) {
            status = _WStatus.expired;
          } else if (expiry.difference(now).inDays <= 30) {
            status = _WStatus.expiring;
          } else {
            status = _WStatus.active;
          }

          final rk = roomKey.toString();
          final brand = item['brand']?.toString() ?? '';
          final hasBrand = brand.isNotEmpty &&
              brand.toLowerCase() != 'unknown' &&
              brand.toUpperCase() != 'N/A';

          out.add(_VaultItem(
            entry: DeviceEntry(
              homeId: homeId,
              homeAddress: address,
              pincode: pincode,
              roomKey: rk,
              roomName: rk.isNotEmpty ? '${rk[0].toUpperCase()}${rk.substring(1)}' : rk,
              raw: item,
            ),
            product: item['product']?.toString() ?? AppStrings.appliance,
            brand: hasBrand ? brand : '',
            homeLabel: homeLabel,
            expiry: expiry,
            status: status,
          ));
        }
      });
    }

    // Most urgent first: expiring (soonest), then expired (latest first),
    // then active (soonest), then no warranty.
    int rank(_WStatus s) => switch (s) {
          _WStatus.expiring => 0,
          _WStatus.expired => 1,
          _WStatus.active => 2,
          _WStatus.none => 3,
        };
    out.sort((a, b) {
      final r = rank(a.status).compareTo(rank(b.status));
      if (r != 0) return r;
      if (a.expiry == null || b.expiry == null) return 0;
      return a.status == _WStatus.expired
          ? b.expiry!.compareTo(a.expiry!)
          : a.expiry!.compareTo(b.expiry!);
    });
    return out;
  }

  Color _colorOf(_WStatus s) => switch (s) {
        _WStatus.active => AppColors.lightSuccess,
        _WStatus.expiring => AppColors.warning,
        _WStatus.expired => AppColors.danger,
        _WStatus.none => AppColors.danger,
      };

  // Writes an edit / removal back into the Hive box so the list updates
  // immediately (the ValueListenableBuilder below listens to the box).
  Future<void> _syncToBox(DeviceEntry e, {bool remove = false}) async {
    for (final key in _homeBox.keys.toList()) {
      final h = _homeBox.get(key);
      if (h == null) continue;

      final map = h.toMap();
      if (map['id']?.toString() != e.homeId) continue;

      final rooms = <String, List<Map<String, dynamic>>>{};
      ((map['rooms'] as Map?) ?? {}).forEach((k, v) {
        rooms[k.toString()] = (v as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
      });

      final list = rooms[e.roomKey];
      if (list == null) return;

      final idx = list.indexWhere(
        (d) => (d['deviceId'] ?? d['_id'])?.toString() == e.deviceId,
      );
      if (idx == -1) return;

      if (remove) {
        list.removeAt(idx);
      } else {
        list[idx] = Map<String, dynamic>.from(e.raw);
      }

      map['rooms'] = rooms;
      await _homeBox.put(key, HomeModel.fromMap(map));
      return;
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Warranty Vault',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: ValueListenableBuilder<Box<HomeModel>>(
        valueListenable: _homeBox.listenable(),
        builder: (context, _, __) {
          final all = _collect();
          int count(_WStatus s) => all.where((v) => v.status == s).length;
          final shown = _filter == null ? all : all.where((v) => v.status == _filter).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _summaryRow(count(_WStatus.active), count(_WStatus.expiring),
                    count(_WStatus.expired), count(_WStatus.none)),
              ),
              const SizedBox(height: 12),
              _filterChips(all.length, count),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? _emptyState(all.isEmpty)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _itemCard(shown[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Summary: 4 small counters ──
  Widget _summaryRow(int active, int expiring, int expired, int none) {
    Widget box(String value, String label, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: AppDecor.flatCard(radius: 14),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        box('$active', 'Active', AppColors.lightSuccess),
        box('$expiring', 'Expiring', AppColors.warning),
        box('$expired', 'Expired', AppColors.danger),
        box('$none', 'None', AppColors.danger),
      ],
    );
  }

  // ── Filter chips ──
  Widget _filterChips(int total, int Function(_WStatus) count) {
    Widget chip(String label, _WStatus? value) {
      final selected = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _filter = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.primary : AppColors.borderMuted),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.onPrimary : AppColors.textSecondary)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          chip('All ($total)', null),
          chip('Active (${count(_WStatus.active)})', _WStatus.active),
          chip('Expiring (${count(_WStatus.expiring)})', _WStatus.expiring),
          chip('Expired (${count(_WStatus.expired)})', _WStatus.expired),
          chip('No warranty (${count(_WStatus.none)})', _WStatus.none),
        ],
      ),
    );
  }

  // ── Three-dot menu (same as Devices tab) ──
  Widget _buildItemMenu(DeviceEntry e) {
    PopupMenuItem<String> entry(
        String value, IconData icon, Color iconColor, String text, Color textColor) {
      return PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: textColor)),
        ]),
      );
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 18),
        color: AppColors.cardBg,
        onSelected: (value) {
          if (value == 'edit') {
            showDeviceEditDialog(context, e, onChanged: () => _syncToBox(e));
          }
          if (value == 'service') {
            showDeviceServiceSheet(context, e,
                mobileNumber: widget.mobileNumber, name: widget.name);
          }
          if (value == 'delete') {
            confirmRemoveDevice(context, e, onChanged: () => _syncToBox(e, remove: true));
          }
        },
        itemBuilder: (context) => [
          entry('edit', Icons.edit_outlined, AppColors.primary, AppStrings.edit,
              AppColors.textPrimary),
          entry('service', Icons.build_rounded, AppColors.primary, AppStrings.findService,
              AppColors.textPrimary),
          entry('delete', Icons.delete_outline, AppColors.danger, AppStrings.remove,
              AppColors.danger),
        ],
      ),
    );
  }

  // ── One device row ──
  Widget _itemCard(_VaultItem v) {
    final color = _colorOf(v.status);
    final imageUrl = v.entry.imageUrl;
    final fallback = Icon(Icons.devices_other_rounded, size: 22, color: AppColors.primary);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showDeviceDetailsSheet(
        context,
        v.entry,
        mobileNumber: widget.mobileNumber,
        name: widget.name,
        onChanged: () => _syncToBox(v.entry),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(imageUrl,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
                  : fallback,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.brand.isEmpty ? v.product : '${v.brand} ${v.product}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(v.homeLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  const SizedBox(height: 6),
                  DeviceWarrantyIndicator(v.entry),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _buildItemMenu(v.entry),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(bool noDevicesAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, size: 44, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(
              noDevicesAtAll ? 'No appliances yet' : 'Nothing in this filter',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              noDevicesAtAll
                  ? 'Add appliances from the Home tab and their warranties will show up here.'
                  : 'Try a different filter.',
              textAlign: TextAlign.center,
              style: AppText.faintCaption,
            ),
          ],
        ),
      ),
    );
  }
}