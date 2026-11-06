// lib/device_details_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/warranty_utils.dart';
import 'widgets/device_details_sheet.dart'; // DeviceEntry + edit/remove/service
import 'device_edit_screen.dart';
import 'services/entity_update_service.dart';
import 'constants/api_config.dart';
import 'services/api_client.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final DeviceEntry entry;
  final String mobileNumber;
  final String name;
  final IconData fallbackIcon;
  final VoidCallback? onChanged; // fires after edit / remove so caller refreshes

  const DeviceDetailsScreen({
    super.key,
    required this.entry,
    required this.mobileNumber,
    this.name = '',
    this.fallbackIcon = Icons.devices_other_rounded,
    this.onChanged,
  });

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  Map<String, dynamic> get _raw => widget.entry.raw;
  Map<String, dynamic>? _lastCreated; // new device data returned after recreate

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── actions (reuse existing logic from device_details_sheet.dart) ──
  void _findService() => showDeviceServiceSheet(
        context,
        widget.entry,
        mobileNumber: widget.mobileNumber,
        name: widget.name,
      );

  Future<File?> _download(String url, String name) async {
    try {
      final r = await http.get(Uri.parse(url));
      if (r.statusCode != 200) return null;
      final f = File('${Directory.systemTemp.path}/$name');
      await f.writeAsBytes(r.bodyBytes);
      return f;
    } catch (_) {
      return null;
    }
  }

  // Re-creates the device with photos, then deletes the old one.
  Future<String?> _recreateWithPhotos(
      DeviceEditData d, String oldDeviceId, String homeId,
      {bool removeCard = false}) async {
    final e = widget.entry;
    try {
      final req =
          http.MultipartRequest('POST', Uri.parse(ApiConfig.productSubmitUrl));
      req.headers.addAll(await ApiClient.authHeaders());

      req.fields['homeId'] = homeId;
      req.fields['address'] = e.homeAddress;
      req.fields['pincode'] = e.pincode;
      req.fields['product'] = d.product;
      req.fields['brand'] = d.brand.isNotEmpty ? d.brand : 'Unknown';
      req.fields['mobile'] = ApiConfig.stripCountryCode(widget.mobileNumber);
      req.fields['warranty'] = d.warranty.isNotEmpty ? d.warranty : 'N/A';
      req.fields['roomName'] = e.roomName.isNotEmpty ? e.roomName : 'Default';
      req.fields['name'] = widget.name;
      if (d.shop.isNotEmpty) req.fields['purchasedShopName'] = d.shop;
      if (d.shopWarranty.isNotEmpty) {
        req.fields['shopWarranty'] = d.shopWarranty;
      }
      if (d.model.isNotEmpty) req.fields['modelNumber'] = d.model;
      if (d.serial.isNotEmpty) req.fields['serialNumber'] = d.serial;

      final stamp = DateTime.now().microsecondsSinceEpoch;

      final img = e.imageUrl;
      if (img != null && img.isNotEmpty) {
        final f = await _download(img, 'main_$stamp.jpg');
        if (f != null) {
          req.files.add(await http.MultipartFile.fromPath('file', f.path));
        }
      }

      if (d.warrantyCard != null) {
        req.files.add(await http.MultipartFile.fromPath(
            'warrantyFile', d.warrantyCard!.path));
      } else if (!removeCard && _warrantyCardUrl != null) {
        final f = await _download(_warrantyCardUrl!, 'card_$stamp.jpg');
        if (f != null) {
          req.files
              .add(await http.MultipartFile.fromPath('warrantyFile', f.path));
        }
      }

      var i = 0;
      for (final u in _photos) {
        if (d.removedExtraUrls.contains(u)) continue;
        final f = await _download(u, 'other_${i++}_$stamp.jpg');
        if (f == null) return 'Could not read an existing photo. Try again.';
        req.files.add(await http.MultipartFile.fromPath('others', f.path));
      }
      for (final f in d.extraPhotos) {
        req.files.add(await http.MultipartFile.fromPath('others', f.path));
      }

      final res = await http.Response.fromStream(await req.send());
      debugPrint('♻️ Recreate status: ${res.statusCode} ${res.body}');
      if (res.statusCode != 200 && res.statusCode != 201) {
        return 'Could not save photos (${res.statusCode})';
      }

      // try to read the newly created device from the response
      _lastCreated = null;
      try {
        final j = jsonDecode(res.body);
        Map? m;
        if (j is Map) {
          for (final k in ['data', 'product', 'device', 'result']) {
            if (j[k] is Map) {
              m = j[k] as Map;
              break;
            }
          }
          m ??= j;
        }
        if (m != null &&
            (m.containsKey('_id') || m.containsKey('deviceId')) &&
            (m.containsKey('otherUrls') || m.containsKey('warrantyUrl'))) {
          _lastCreated = Map<String, dynamic>.from(m);
        }
      } catch (_) {}

      final del = await ApiClient.delete(ApiConfig.commonDeleteUrl,
          body: {'type': 'PRODUCT', 'id': oldDeviceId});
      debugPrint('🗑️ Old device delete: ${del.statusCode}');
      return null;
    } catch (err) {
      return 'Network error: $err';
    }
  }

  Future<void> _edit() async {
    final e = widget.entry;
    final deviceId =
        (_raw['deviceId'] ?? _raw['_id'] ?? _raw['id'])?.toString();
    final homeId = e.homeId;
    bool recreated = false;

    final result = await Navigator.push<DeviceEditData>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceEditScreen(
          photoUrl: e.imageUrl,
          fallbackIcon: widget.fallbackIcon,
          existingExtraUrls: _photos,
          existingWarrantyUrl: _warrantyCardUrl,
          initial: _baseData(),
          onSave: (d) async {
            if (deviceId == null) return 'Device id not found';
            if (homeId == null || homeId.isEmpty) return 'Home id not found';

            final photosChanged = d.warrantyCard != null ||
    d.removeWarrantyCard ||
    d.extraPhotos.isNotEmpty ||
    d.removedExtraUrls.isNotEmpty;

            if (photosChanged) {
              final err = await _recreateWithPhotos(d, deviceId, homeId,
    removeCard: d.removeWarrantyCard);
              if (err == null) recreated = true;
              return err;
            }

            final res = await EntityUpdateService.update(
              homeId: homeId,
              deviceId: deviceId,
              product: d.product,
              brand: d.brand,
              warranty: d.warranty,
              purchasedShopName: d.shop,
              shopWarranty: d.shopWarranty,
              modelNumber: d.model,
              serialNumber: d.serial,
            );
            return res['success'] == true
                ? null
                : (res['message']?.toString() ?? 'Update failed');
          },
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (recreated) {
      widget.onChanged?.call();
      final fresh = _lastCreated;
      if (fresh != null) {
        // stay on this screen, swap in the new device data
                setState(() {
          for (final k in ['deviceId', '_id', 'id', 'otherUrls']) {
            _raw.remove(k);
          }
          if (result.removeWarrantyCard) {
            for (final k in ['warrantyUrl', 'warrantyFileUrl', 'warrantyCardUrl']) {
              _raw.remove(k);
            }
          }
          _raw.addAll(fresh);
        });
      } else {
        Navigator.pop(context);
      }
      return;
    }

    setState(() {
      _raw['product'] = result.product;
      _raw['brand'] = result.brand;
      _raw['warranty'] = result.warranty;
      _raw['purchasedShopName'] = result.shop;
      _raw['shopWarranty'] = result.shopWarranty;
      _raw['modelNumber'] = result.model;
      _raw['serialNumber'] = result.serial;
    });
    widget.onChanged?.call();
  }

  void _remove() => confirmRemoveDevice(
        context,
        widget.entry,
        onChanged: () {
          widget.onChanged?.call();
          if (mounted) Navigator.pop(context);
        },
      );

  // ── data helpers ──
  String _s(List<String> keys, {String fallback = '-'}) {
    for (final k in keys) {
      final v = _raw[k]?.toString().trim() ?? '';
      if (v.isNotEmpty &&
          v.toUpperCase() != 'N/A' &&
          v.toLowerCase() != 'unknown') {
        return v;
      }
    }
    return fallback;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  DateTime? get _expiry => WarrantyUtils.parseExpiry(
        _raw['warranty']?.toString(),
        referenceDate: DateTime.tryParse(_raw['createdAt']?.toString() ?? ''),
      );

  // Warranty card image = backend `warrantyUrl`
  String? get _warrantyCardUrl {
    for (final k in ['warrantyUrl', 'warrantyFileUrl', 'warrantyCardUrl']) {
      final v = _raw[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return null;
  }

  // Extra photos = backend `otherUrls`
  List<String> get _photos {
    final raw = _raw['otherUrls'];
    if (raw is! List) return [];
    return raw
        .map((e) =>
            e is Map ? (e['url'] ?? e['imageUrl'])?.toString() : e?.toString())
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .toList();
  }

  // ── theme-aware colors ──
  Color get _purple => AppColors.lightPurple;

  LinearGradient get _bgGradient => ThemeController.isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16406B), Color(0xFF0F2347), Color(0xFF0A1628)],
          stops: [0, 0.4, 1],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4BA3F0),
            Color(0xFF7EC0F8),
            Color(0xFFB8DFFC),
            Color(0xFFEAF6FF),
            Color(0xFFF5F8FF),
          ],
          // stops are squeezed into the top half, so the blue fades out
          // like the home header and the rest of the page is plain F5F8FF
          stops: [0, 0.12, 0.25, 0.37, 0.5],
        );

  // =====================================================================
  // BUILD
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.notifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Container(
          decoration: BoxDecoration(gradient: _bgGradient),
          child: SafeArea(
            child: Column(
              children: [
                _appBar(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _heroCard(),
                      const SizedBox(height: 12),
                      _actionsCard(),
                      const SizedBox(height: 12),
                      _infoCard(),
                      const SizedBox(height: 12),
                      _locationCard(),
                      const SizedBox(height: 12),
                      _documentsCard(context),
                      const SizedBox(height: 12),
                      _removeButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text('Device Details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  // ── Reusable card + header ──
  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: ThemeController.isDark ? 0.18 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: child,
      );

  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      );

  // ── Warranty status chip (never overflows: text wraps/ellipsis) ──
  Widget _statusChip() {
    final expiry = _expiry;
    final Color color;
    final IconData icon;
    final String label;

    if (expiry == null) {
      color = AppColors.danger;
      icon = Icons.gpp_bad_outlined;
      label = 'No Warranty';
    } else if (expiry.isAfter(DateTime.now())) {
      final soon = expiry.difference(DateTime.now()).inDays <= 30;
      color = soon ? AppColors.warning : AppColors.success;
      icon = Icons.verified_user_rounded;
      label = soon ? 'Expiring Soon' : 'Warranty Active';
    } else {
      color = AppColors.danger;
      icon = Icons.gpp_bad_outlined;
      label = 'Warranty Expired';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  // ── Hero ──
  Widget _heroCard() {
    final imageUrl = widget.entry.imageUrl;
    final fallback =
        Icon(widget.fallbackIcon, size: 48, color: AppColors.primary);
    return _card(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.primaryFaint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: fallback))
                : Center(child: fallback),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s(['product'], fallback: 'Appliance'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: _statusChip()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Find Service / Edit Device ──
  Widget _actionsCard() => _card(
        child: Row(
          children: [
            Expanded(
              child: _actionButton(Icons.build_rounded, 'Find Service',
                  AppColors.primary, _findService),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  _actionButton(Icons.edit_outlined, 'Edit Device', _purple, _edit),
            ),
          ],
        ),
      );

  Widget _actionButton(
          IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(width: 8),
                  Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      );

  // ── Device Information ──
  Widget _infoCard() {
    final installRaw =
        _raw['installationDate'] ?? _raw['purchaseDate'] ?? _raw['createdAt'];
    final installDate = DateTime.tryParse(installRaw?.toString() ?? '');

    return _card(
      child: Column(
        children: [
          _sectionHeader(Icons.info_outline_rounded, 'Device Information'),
          const SizedBox(height: 8),
          _infoRow('Device Type', value: _s(['product'])),
          _infoRow('Brand', value: _s(['brand'])),
          _infoRow('Purchased From', value: _s(['purchasedShopName'])),
          _infoRow('Shop Warranty', value: _s(['shopWarranty'])),
          _infoRow('Model Number', value: _s(['modelNumber'])),
          _infoRow('Serial Number', value: _s(['serialNumber'])),
          _infoRow('Installation Date', value: _fmt(installDate)),
          _infoRow('Warranty Status', trailing: _statusChip()),
          _infoRow('Warranty Valid Till', value: _fmt(_expiry), last: true),
        ],
      ),
    );
  }

  Widget _infoRow(String label,
          {String? value, Widget? trailing, bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Text(label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
            ),
            const SizedBox(width: 10),
                        Expanded(
              flex: 5,
              child: trailing != null
                  ? Align(alignment: Alignment.centerRight, child: trailing)
                  : Padding(
                      padding: EdgeInsets.only(
                          right: (value == null || value == '-') ? 24 : 0),
                      child: Text(value ?? '-',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ),
            ),
          ],
        ),
      );

  // ── Location ──
  Widget _locationCard() {
    final building = widget.entry.homeAddress.split(',').first.trim();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.location_on_outlined, 'Location'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.cardBgAlt,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _locTile(Icons.apartment_rounded, 'Building',
                building.isEmpty ? '-' : building, AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _locTile(IconData icon, String label, String value, Color color) =>
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );

  // =====================================================================
  // PHOTOS: direct add / replace / delete
  // =====================================================================
  DeviceEditData _baseData() => DeviceEditData(
        product: _s(['product'], fallback: ''),
        brand: _s(['brand'], fallback: ''),
        warranty: _s(['warranty'], fallback: ''),
        shop: _s(['purchasedShopName'], fallback: ''),
        shopWarranty: _s(['shopWarranty'], fallback: ''),
        model: _s(['modelNumber'], fallback: ''),
        serial: _s(['serialNumber'], fallback: ''),
      );

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _applyPhotoChange(DeviceEditData d,
      {bool removeCard = false, required String okMsg}) async {
    final deviceId =
        (_raw['deviceId'] ?? _raw['_id'] ?? _raw['id'])?.toString();
    final homeId = widget.entry.homeId;
    if (deviceId == null) return _toast('Device id not found');
    if (homeId == null || homeId.isEmpty) return _toast('Home id not found');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final err =
        await _recreateWithPhotos(d, deviceId, homeId, removeCard: removeCard);
    if (!mounted) return;
    Navigator.of(context).pop(); // close loader
    if (err != null) return _toast(err);

    widget.onChanged?.call(); // refresh list in background

    final fresh = _lastCreated;
    if (fresh != null) {
      // stay on this screen, swap in the new device data
            setState(() {
        for (final k in ['deviceId', '_id', 'id', 'otherUrls']) {
          _raw.remove(k);
        }
        if (removeCard) {
          for (final k in ['warrantyUrl', 'warrantyFileUrl', 'warrantyCardUrl']) {
            _raw.remove(k);
          }
        }
        _raw.addAll(fresh);
      }); 
      _toast(okMsg);
    } else {
      // could not read the new device from the response
      _toast(okMsg);
      Navigator.pop(context);
    }
  }

  Future<void> _pickCard() async {
    final p = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600);
    if (p == null) return;
    final d = _baseData()..warrantyCard = File(p.path);
    await _applyPhotoChange(d, okMsg: 'Warranty card saved');
  }

  Future<void> _deleteCard() async {
    if (!await _confirm('Delete warranty card?', 'This cannot be undone.')) {
      return;
    }
    await _applyPhotoChange(_baseData(),
        removeCard: true, okMsg: 'Warranty card deleted');
  }

  Future<void> _addPhotos() async {
    final left = 10 - _photos.length;
    if (left <= 0) return _toast('Maximum 10 photos');
    final picked = await ImagePicker()
        .pickMultiImage(imageQuality: 70, maxWidth: 1280, maxHeight: 1280);
    if (picked.isEmpty) return;
    final d = _baseData()
      ..extraPhotos = picked.take(left).map((x) => File(x.path)).toList();
    await _applyPhotoChange(d, okMsg: 'Photos added');
  }

  Future<void> _deletePhoto(String url) async {
    if (!await _confirm('Delete this photo?', 'This cannot be undone.')) return;
    final d = _baseData()..removedExtraUrls = [url];
    await _applyPhotoChange(d, okMsg: 'Photo deleted');
  }

  // ── Photo cards (icon rows: thumbnail + view / download / delete) ──
  Widget _pillBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _fileRow({
    required IconData fallbackIcon,
    required Color color,
    required String? thumbUrl,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onView,
    required VoidCallback onDownload,
    required VoidCallback onDelete,
  }) {
    Widget act(IconData i, Color c, VoidCallback f) => IconButton(
          onPressed: enabled ? f : null,
          icon: Icon(i,
              size: 22,
              color: enabled ? c : AppColors.textMuted.withValues(alpha: 0.4)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          visualDensity: VisualDensity.compact,
        );

    final placeholder = Icon(fallbackIcon, color: color, size: 22);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBgAlt,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: enabled ? onView : null,
            child: Container(
              width: 48,
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: (thumbUrl != null && thumbUrl.isNotEmpty)
                  ? Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      errorBuilder: (_, __, ___) => Center(child: placeholder),
                    )
                  : Center(child: placeholder),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          act(Icons.visibility_outlined, AppColors.primary, onView),
          act(Icons.file_download_outlined, AppColors.primary, onDownload),
          act(Icons.delete_outline_rounded, AppColors.textPrimary, onDelete),
        ],
      ),
    );
  }

  // ── Warranty Card + Extra Photos (two cards, each with heading) ──
  Widget _documentsCard(BuildContext context) => Column(
        children: [
          _warrantyCardCard(context),
          const SizedBox(height: 12),
          _extraPhotosCard(context),
        ],
      );

  Widget _warrantyCardCard(BuildContext context) {
    final url = _warrantyCardUrl;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.verified_outlined,
            'Warranty Card',
            trailing: url == null
                ? _pillBtn(Icons.add_a_photo_outlined, 'Upload',
                    AppColors.primary, _pickCard)
                : _pillBtn(Icons.edit_outlined, 'Replace', _purple, _pickCard),
          ),
          const SizedBox(height: 12),
          _fileRow(
            fallbackIcon: Icons.verified_outlined,
            color: AppColors.danger,
            thumbUrl: url,
            title: 'Warranty Card',
            subtitle: url == null ? 'Not added' : '1 image',
            enabled: url != null,
            onView: () => _openViewer(context, [url!], 0),
            onDownload: () => _downloadAll([url!], 'warranty_card'),
            onDelete: _deleteCard,
          ),
        ],
      ),
    );
  }

  Widget _extraPhotosCard(BuildContext context) {
    final photos = _photos;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.photo_library_outlined,
            'Extra Photos (${photos.length})',
            trailing: photos.length < 10
    ? _pillBtn(Icons.add_a_photo_outlined, 'Upload',
        AppColors.primary, _addPhotos)
    : null,
          ),
          const SizedBox(height: 12),
          if (photos.isEmpty)
            Text('No photos added',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14))
          else ...[
            _fileRow(
              fallbackIcon: Icons.photo_library_outlined,
              color: _purple,
              thumbUrl: photos.first,
              title: 'Device Photos (${photos.length})',
              subtitle:
                  '${photos.length} image${photos.length > 1 ? 's' : ''}',
              enabled: true,
              onView: () =>
                  _openViewer(context, photos, 0, onDelete: _deletePhoto),
              onDownload: () => _downloadAll(photos, 'device_photo'),
              onDelete: _deleteAllPhotos,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteAllPhotos() async {
    if (!await _confirm('Delete all photos?', 'This cannot be undone.')) return;
    final d = _baseData()..removedExtraUrls = List<String>.from(_photos);
    await _applyPhotoChange(d, okMsg: 'Photos deleted');
  }

  Future<void> _downloadAll(List<String> urls, String prefix) async {
    _toast('Downloading...');
    var ok = 0;
    for (var i = 0; i < urls.length; i++) {
      final f = await _download(urls[i], '${prefix}_${i + 1}.jpg');
      if (f == null) continue;
      try {
        await Gal.putImage(f.path); // saves to Gallery
        ok++;
      } catch (_) {}
    }
    _toast(ok == urls.length
        ? 'Saved $ok image(s) to Gallery'
        : 'Some downloads failed');
  }

  // Swipe viewer. If onDelete is given, a delete icon shows for current photo.
  void _openViewer(BuildContext context, List<String> photos, int start,
      {Future<void> Function(String url)? onDelete}) {
    final controller = PageController(initialPage: start);
    var current = start;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              title: photos.length > 1
                  ? Text('${current + 1} / ${photos.length}',
                      style: const TextStyle(fontSize: 16))
                  : null,
              actions: [
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () {
                      final u = photos[current];
                      Navigator.pop(ctx);
                      onDelete(u);
                    },
                  ),
              ],
            ),
            body: PageView.builder(
              controller: controller,
              itemCount: photos.length,
              onPageChanged: (i) => setS(() => current = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(
                    child: Image.network(photos[i], fit: BoxFit.contain)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Remove ──
  Widget _removeButton() => InkWell(
        onTap: _remove,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text('Remove Device',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      );
}