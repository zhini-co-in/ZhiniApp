// lib/widgets/device_details_sheet.dart
//
// Common device model + details sheet + actions (edit / find service /
// book / remove). Any screen that shows a device card calls
// showDeviceDetailsSheet(...) so the behaviour is identical everywhere.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_config.dart';
import '../constants/app_strings.dart';
import '../services/api_client.dart';
import '../services/entity_update_service.dart';
import '../theme/app_theme.dart';
import '../utils/warranty_ocr.dart';
import '../utils/warranty_utils.dart';
import 'app_dialog_field.dart';
import 'confirm_action_dialog.dart';
import 'service_provider_card.dart';
import 'warranty_badge.dart';

// ---------------------------------------------------------------------
// MODEL — one appliance + the home it belongs to
// ---------------------------------------------------------------------
class DeviceEntry {
  final String? homeId;
  final String homeAddress;
  final String pincode;
  final String roomKey; // still needed by the backend (delete API)
  final String roomName;
  final Map<String, dynamic> raw;

  DeviceEntry({
    required this.homeId,
    required this.homeAddress,
    required this.pincode,
    required this.roomKey,
    required this.roomName,
    required this.raw,
  });

  String get product => raw['product']?.toString().trim().isNotEmpty == true
      ? raw['product'].toString()
      : 'Appliance';
  String get brand => raw['brand']?.toString() ?? '';
  String? get imageUrl => raw['imageUrl']?.toString();
  String? get deviceId => (raw['deviceId'] ?? raw['_id'])?.toString();

  // Warranty card image URL. The backend key name is not known for sure, so
  // a few likely names are checked. Change/trim this list to match your API.
  String? get warrantyCardUrl {
    const keys = [
      'warrantyCardUrl',
      'warrantyFileUrl',
      'warrantyFile',
      'warrantyCard',
      'warrantyImageUrl',
      'warrantyUrl',
    ];
    for (final k in keys) {
      final v = raw[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v.toUpperCase() != 'N/A') return v;
    }
    return null;
  }

  DateTime? get createdAt => DateTime.tryParse(raw['createdAt']?.toString() ?? '');

  DateTime? get expiry =>
      WarrantyUtils.parseExpiry(raw['warranty']?.toString(), referenceDate: createdAt);

  bool get isUnderWarranty => expiry != null && expiry!.isAfter(DateTime.now());
  bool get isExpired => expiry != null && !expiry!.isAfter(DateTime.now());
  bool get warrantyUnknown => expiry == null;
  bool get isAttention => expiry != null && expiry!.difference(DateTime.now()).inDays <= 30;

  bool get isServiceDue {
    if (raw['serviceDue'] == true) return true;
    final nextDue = DateTime.tryParse(raw['nextServiceDue']?.toString() ?? '');
    if (nextDue != null) return !nextDue.isAfter(DateTime.now());
    return false;
  }

  int get ageYears {
    final created = createdAt;
    if (created == null) return 0;
    return (DateTime.now().difference(created).inDays / 365).floor();
  }

  String get ageLabel {
    final created = createdAt;
    if (created == null) return '';
    final days = DateTime.now().difference(created).inDays;
    if (days < 30) return '$days d';
    final years = days / 365;
    if (years < 1) return '${(days / 30).round()} mo';
    return '${years.toStringAsFixed(years >= 10 ? 0 : 1)} yrs';
  }

  String get purchasedYear => createdAt != null ? createdAt!.year.toString() : 'Unknown';
}

// ---------------------------------------------------------------------
// SMALL SHARED WIDGET — warranty indicator
// ---------------------------------------------------------------------
class DeviceWarrantyIndicator extends StatelessWidget {
  final DeviceEntry entry;
  const DeviceWarrantyIndicator(this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e.warrantyUnknown) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gpp_bad_outlined, size: 16, color: AppColors.danger),
          SizedBox(width: 4),
          Text('No warranty',
              style: TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      );
    }
    if (e.isUnderWarranty) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, size: 16, color: AppColors.lightSuccess),
          SizedBox(width: 4),
          Text('Warranty active',
              style: TextStyle(
                  color: AppColors.lightSuccess, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      );
    }
    return WarrantyBadge(expiry: e.expiry);
  }
}

// ---------------------------------------------------------------------
// WARRANTY CARD — full screen viewer (pinch to zoom)
// ---------------------------------------------------------------------
void showWarrantyCardViewer(BuildContext context,
    {String? url, File? file, String title = 'Warranty card'}) {
  if (url == null && file == null) return;

  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: file != null
                      ? Image.file(file, fit: BoxFit.contain)
                      : Image.network(
                          url!,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(color: AppColors.primary)),
                          errorBuilder: (_, _, _) => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Could not load the warranty card',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70)),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// =====================================================================
// PUBLIC ENTRY POINTS
// =====================================================================

/// Opens the details sheet. [onChanged] fires after an edit / remove so the
/// caller can refresh its list.
void showDeviceDetailsSheet(
  BuildContext context,
  DeviceEntry e, {
  required String mobileNumber,
  String name = '',
  VoidCallback? onChanged,
}) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String fmt(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  Widget infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBgAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(label, style: AppText.caption),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  final now = DateTime.now();
  final expiry = e.expiry;
  final created = e.createdAt;
  final cardUrl = e.warrantyCardUrl;
  final hasBrand =
      e.brand.isNotEmpty && e.brand.toLowerCase() != 'unknown' && e.brand.toUpperCase() != 'N/A';
  final rawWarranty = e.raw['warranty']?.toString().trim() ?? '';
  final hasRawWarranty = rawWarranty.isNotEmpty && rawWarranty.toUpperCase() != 'N/A';

  final Color accent;
  final String statusLabel;
  final IconData statusIcon;
  String bigNumber = '—';
  String bigUnit = '';
  double? progress;

  if (expiry == null) {
    accent = AppColors.danger;
    statusLabel = 'No warranty';
    statusIcon = Icons.gpp_bad_outlined;
    bigUnit = 'No warranty on record';
  } else if (e.isUnderWarranty) {
    final days = expiry.difference(now).inDays;
    accent = days <= 30 ? AppColors.warning : AppColors.lightSuccess;
    statusLabel = days <= 30 ? 'Expiring soon' : 'Warranty active';
    statusIcon = Icons.verified_user_rounded;
    bigNumber = days > 0 ? '$days' : '0';
    bigUnit = days == 1 ? 'day left' : 'days left';
  } else {
    accent = AppColors.danger;
    statusLabel = 'Warranty expired';
    statusIcon = Icons.event_busy_rounded;
    bigNumber = '${now.difference(expiry).inDays}';
    bigUnit = 'days ago';
  }

  if (created != null && expiry != null) {
    final total = expiry.difference(created).inDays;
    final used = now.difference(created).inDays;
    progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 1.0;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cardBg,
    isScrollControlled: true,
    shape: AppDecor.sheetShape,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // ---------- HERO CARD ----------
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withValues(alpha: 0.22), AppColors.cardBgAlt],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: (e.imageUrl != null && e.imageUrl!.isNotEmpty)
                            ? () => showWarrantyCardViewer(context,
                                url: e.imageUrl, title: e.product)
                            : null,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                              ? Image.network(e.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                      Icons.devices_other_rounded,
                                      size: 28,
                                      color: AppColors.textFaint))
                              : const Icon(Icons.devices_other_rounded,
                                  size: 28, color: AppColors.textFaint),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.product,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.dialogTitle),
                            const SizedBox(height: 2),
                            Text(hasBrand ? e.brand : 'Brand not added', style: AppText.caption),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 13, color: accent),
                                  const SizedBox(width: 5),
                                  Text(statusLabel,
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(sheetContext),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(bigNumber,
                          style: TextStyle(
                              color: accent, fontSize: 38, height: 1, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(bigUnit, style: AppText.caption),
                      ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: AppColors.borderSubtle,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(fmt(created!), style: AppText.caption),
                        Text(fmt(expiry!), style: AppText.caption),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ---------- SERVICE DUE BANNER ----------
            if (e.isServiceDue) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.build_rounded, size: 16, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Service is due for this appliance',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],

            // ---------- 2x2 INFO TILES ----------
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: infoTile(Icons.sell_outlined, 'Brand', hasBrand ? e.brand : 'Not added')),
                const SizedBox(width: 10),
                Expanded(
                  child: infoTile(Icons.calendar_today_rounded, 'Added on',
                      created != null ? fmt(created) : 'Unknown'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: infoTile(Icons.hourglass_bottom_rounded, 'Device age',
                      e.ageLabel.isNotEmpty ? e.ageLabel : 'Unknown'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: infoTile(Icons.description_outlined, 'Warranty period',
                      hasRawWarranty ? rawWarranty : 'Not added'),
                ),
              ],
            ),

            // ---------- WARRANTY CARD (only if one was uploaded) ----------
            if (cardUrl != null) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () => showWarrantyCardViewer(context, url: cardUrl),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.borderSubtle,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          cardUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.receipt_long_rounded,
                              size: 24, color: AppColors.textFaint),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Warranty card', style: AppText.caption),
                            SizedBox(height: 2),
                            Text('Tap to view',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_full_rounded, size: 18, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],

            // ---------- LOCATION ----------
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBgAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.home_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Home address', style: AppText.caption),
                        const SizedBox(height: 2),
                        Text(
                          e.pincode.isNotEmpty ? '${e.homeAddress} · ${e.pincode}' : e.homeAddress,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---------- ACTIONS ----------
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showDeviceEditDialog(context, e, onChanged: onChanged);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                    label: const Text(AppStrings.edit,
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showDeviceServiceSheet(context, e, mobileNumber: mobileNumber, name: name);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.build_rounded, size: 16, color: AppColors.onPrimary),
                    label: const Text(AppStrings.findService,
                        style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  confirmRemoveDevice(context, e, onChanged: onChanged);
                },
                icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                label: const Text(AppStrings.remove,
                    style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// =====================================================================
// EDIT — product, brand, warranty + warranty card (view / change / OCR)
// =====================================================================
void showDeviceEditDialog(BuildContext context, DeviceEntry e, {VoidCallback? onChanged}) {
  if (e.deviceId == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.couldNotRemoveAppliance)));
    return;
  }

  final oldWarranty = e.raw['warranty']?.toString().trim() ?? '';
  final hadWarranty = oldWarranty.isNotEmpty && oldWarranty.toUpperCase() != 'N/A';
  final existingCardUrl = e.warrantyCardUrl;

  final productController = TextEditingController(text: e.product);
  final brandController = TextEditingController(text: e.brand);
  final warrantyController = TextEditingController(text: hadWarranty ? oldWarranty : '');
  bool isSaving = false;

  // warranty card state (only a NEW pick is uploaded)
  File? pendingCard;
  bool scanningCard = false;
  String? cardMsg;
  bool cardMsgOk = false;

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final hasCard = pendingCard != null || existingCardUrl != null;

        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: AppDecor.dialogShape,
          title: const Text(AppStrings.editAppliance, style: AppText.dialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppDialogField(controller: productController, hint: AppStrings.productNameHint),
                const SizedBox(height: 10),
                AppDialogField(controller: brandController, hint: AppStrings.brandHint),
                const SizedBox(height: 10),
                AppDialogField(
                    controller: warrantyController, hint: AppStrings.warrantyOptionalHint),
                const SizedBox(height: 14),

                // ---- warranty card row ----
                Row(
                  children: [
                    if (hasCard)
                      GestureDetector(
                        onTap: () => showWarrantyCardViewer(
                          context,
                          url: pendingCard == null ? existingCardUrl : null,
                          file: pendingCard,
                        ),
                        child: Container(
                          width: 56,
                          height: 56,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: AppColors.borderSubtle,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: pendingCard != null
                              ? Image.file(pendingCard!, fit: BoxFit.cover)
                              : Image.network(
                                  existingCardUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                      Icons.receipt_long_rounded,
                                      size: 24,
                                      color: AppColors.textFaint),
                                ),
                        ),
                      ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (scanningCard || isSaving)
                            ? null
                            : () async {
                                final picked = await ImagePicker().pickImage(
                                    source: ImageSource.gallery, imageQuality: 80);
                                if (picked == null) return;

                                final file = File(picked.path);
                                setDialogState(() {
                                  pendingCard = file;
                                  scanningCard = true;
                                  cardMsg = null;
                                });

                                // OCR -> auto-fill warranty period
                                final period = await WarrantyOcr.extractPeriod(file);
                                setDialogState(() {
                                  scanningCard = false;
                                  if (period != null) {
                                    warrantyController.text = period;
                                    cardMsg = 'Warranty detected: $period';
                                    cardMsgOk = true;
                                  } else {
                                    cardMsg =
                                        'Could not read warranty period. Please enter it manually.';
                                    cardMsgOk = false;
                                  }
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                        icon: scanningCard
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : Icon(
                                hasCard ? Icons.sync_rounded : Icons.add_a_photo_outlined,
                                size: 16,
                                color: AppColors.primary,
                              ),
                        label: Text(
                          scanningCard
                              ? 'Reading card...'
                              : hasCard
                                  ? 'Change card'
                                  : AppStrings.uploadWarrantyCard,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.linkAction,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cardMsg != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    cardMsg!,
                    style: TextStyle(
                      color: cardMsgOk ? AppColors.success : AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: (isSaving || scanningCard)
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);

                      // empty -> 'N/A' (same as manual add)
                      final newWarranty = warrantyController.text.trim().isEmpty
                          ? 'N/A'
                          : warrantyController.text.trim();
                      final oldNormalized = oldWarranty.isEmpty ? 'N/A' : oldWarranty;
                      final warrantyChanged = newWarranty != oldNormalized;

                      final result = await EntityUpdateService.update(
                        homeId: e.homeId,
                        deviceId: e.deviceId,
                        product: productController.text.trim().isNotEmpty
                            ? productController.text.trim()
                            : null,
                        brand: brandController.text.trim().isNotEmpty
                            ? brandController.text.trim()
                            : null,
                        warranty: warrantyChanged ? newWarranty : null,
                        warrantyFile: pendingCard, // NEW — null = card unchanged
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(result['success'] == true
                                ? AppStrings.applianceUpdated
                                : (result['message']?.toString() ?? AppStrings.updateFailed))),
                      );
                      if (result['success'] == true) {
                        e.raw['product'] = productController.text.trim();
                        e.raw['brand'] = brandController.text.trim();
                        if (warrantyChanged) e.raw['warranty'] = newWarranty;
                        onChanged?.call();
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.textPrimary, strokeWidth: 2))
                  : const Text(AppStrings.save, style: TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        );
      },
    ),
  );
}

// =====================================================================
// REMOVE
// =====================================================================
Future<void> confirmRemoveDevice(BuildContext context, DeviceEntry e, {VoidCallback? onChanged}) async {
  final ok = await showConfirmActionDialog(
    context,
    title: AppStrings.removeApplianceQ,
    content: AppStrings.removeApplianceContent(e.product, e.roomName),
  );
  if (ok != true) return;
  if (!context.mounted) return;

  if (e.deviceId == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.couldNotRemoveAppliance)));
    return;
  }

  try {
    final url = ApiConfig.commonDeleteUrl;
    final body = {'type': 'PRODUCT', 'id': e.deviceId};
    debugPrint('🗑️ DELETE $url body=$body');

    final response = await ApiClient.delete(url, body: body);
    debugPrint('🗑️ Status: ${response.statusCode} | Body: ${response.body}');
    if (!context.mounted) return;

    if (response.statusCode == 200 || response.statusCode == 204) {
      onChanged?.call();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppStrings.applianceRemoved(e.product))));
    } else {
      String msg = AppStrings.couldNotRemoveAppliance;
      try {
        final data = jsonDecode(response.body);
        msg = data['message']?.toString() ?? msg;
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (err) {
    debugPrint('❌ Delete device error: $err');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.networkError)));
    }
  }
}

// =====================================================================
// SERVICE SHEET (+ booking)
// =====================================================================
Future<void> _callNumber(String phone) async {
  try {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (_) {}
}

Future<void> _openMapDirections(String address) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<List<Map<String, dynamic>>> _fetchNearbyProviders(DeviceEntry e) async {
  try {
    final response = await ApiClient.post(ApiConfig.nearbyServiceUrl, body: {
      'brand': e.brand,
      'product': e.product,
      'pincode': e.pincode,
      'isUnderWarranty': e.isUnderWarranty,
    });
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['data'] != null) {
        final rawData = data['data'];
        final List<dynamic> rawList = rawData is List ? rawData : [rawData];
        return rawList.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      }
    }
  } catch (err) {
    debugPrint('❌ Nearby service fetch error: $err');
  }
  return [];
}

void showDeviceServiceSheet(
  BuildContext context,
  DeviceEntry e, {
  required String mobileNumber,
  String name = '',
}) {
  final providersFuture = _fetchNearbyProviders(e)
      .timeout(const Duration(seconds: 30), onTimeout: () => <Map<String, dynamic>>[]);

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cardBg,
    isScrollControlled: true,
    shape: AppDecor.sheetShape,
    builder: (sheetContext) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: providersFuture,
        builder: (ctx, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final providers = snapshot.data ?? [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    e.isUnderWarranty
                        ? AppStrings.authorizedServiceCenters
                        : AppStrings.localRepairProviders,
                    style: AppText.dialogTitle),
                const SizedBox(height: 2),
                Text(AppStrings.productPincode(e.product, e.pincode), style: AppText.caption),
                const SizedBox(height: 16),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                else if (providers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(AppStrings.noProvidersFound, style: AppText.faintCaption),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: providers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = providers[i];
                        final phone = (p['mobile'] ?? p['phone'])?.toString();
                        final address = p['address']?.toString();
                        final ratingRaw = p['rating'];
                        final rating = ratingRaw != null && ratingRaw.toString() != 'N/A'
                            ? double.tryParse(ratingRaw.toString())
                            : null;
                        final hasPhone = phone != null && phone.isNotEmpty && phone != 'N/A';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ServiceProviderCard(
                              name: p['name']?.toString() ?? AppStrings.notAvailable,
                              address: address,
                              phone: phone,
                              rating: rating,
                              onCall: hasPhone ? () => _callNumber(phone) : null,
                              onDirections: (address != null &&
                                      address.isNotEmpty &&
                                      address != 'Address not available')
                                  ? () => _openMapDirections(address)
                                  : null,
                            ),
                            // Book button -> LOCAL (out of warranty) only
                            if (!e.isUnderWarranty) ...[
                              const SizedBox(height: 6),
                              ElevatedButton.icon(
                                onPressed: hasPhone
                                    ? () => _openBookingDialog(
                                          context, sheetContext, p, e, mobileNumber, name)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                icon: const Icon(Icons.calendar_month_rounded,
                                    size: 15, color: AppColors.textPrimary),
                                label: const Text('Book this provider',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<bool> _submitServiceTicket(
  BuildContext context, {
  required Map<String, dynamic> provider,
  required DeviceEntry device,
  required String mobileNumber,
  required String name,
  String? availableTime,
}) async {
  final providerMobile = (provider['mobile'] ?? provider['phone'])?.toString();
  if (providerMobile == null || providerMobile.isEmpty || providerMobile == 'N/A') {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('This provider has no contact number on file.')));
    return false;
  }

  final label = device.brand.isNotEmpty && device.brand.toUpperCase() != 'N/A'
      ? '${device.brand} ${device.product}'
      : device.product;

  try {
    final response = await ApiClient.post(ApiConfig.createServiceTicketUrl, body: {
      'customerName': name.isNotEmpty ? name : 'Customer',
      'cust_number': ApiConfig.stripCountryCode(mobileNumber),
      'address': device.homeAddress,
      'description': '$label — Out of warranty. Room: ${device.roomName}.',
      'providerMobile': providerMobile,
      if (availableTime != null && availableTime.trim().isNotEmpty)
        'availableTime': availableTime.trim(),
    });
    if (!context.mounted) return false;

    if (response.statusCode == 200 || response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service booked ✅ — the provider will reach out shortly.')));
      return true;
    }
    final data = jsonDecode(response.body);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Could not book this provider.')));
    return false;
  } catch (err) {
    debugPrint('❌ Create ticket error: $err');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.networkError)));
    }
    return false;
  }
}

void _openBookingDialog(
  BuildContext context,
  BuildContext sheetContext,
  Map<String, dynamic> provider,
  DeviceEntry device,
  String mobileNumber,
  String name,
) {
  final timeController = TextEditingController();
  bool isSubmitting = false;

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text('Confirm booking', style: AppText.dialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${provider['name'] ?? 'Provider'} will be notified about your ${device.product}.',
                style: AppText.faintCaption),
            const SizedBox(height: 14),
            AppDialogField(
              controller: timeController,
              hint: 'Preferred time (optional, e.g. Tomorrow 10 AM)',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: isSubmitting
                ? null
                : () async {
                    setDialogState(() => isSubmitting = true);
                    final ok = await _submitServiceTicket(
                      context,
                      provider: provider,
                      device: device,
                      mobileNumber: mobileNumber,
                      name: name,
                      availableTime: timeController.text,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (ok && sheetContext.mounted) Navigator.pop(sheetContext);
                  },
            child: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                : const Text('Book', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    ),
  );
}