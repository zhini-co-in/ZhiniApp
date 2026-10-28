// lib/room_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants/api_config.dart';
import 'scan_tab.dart';
import 'services/api_client.dart';
import 'services/entity_update_service.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/confirm_action_dialog.dart';
import 'widgets/service_provider_card.dart';
import 'widgets/warranty_badge.dart';

/// Appliances list of one room (+ edit / delete / book service).
class RoomDetailScreen extends StatefulWidget {
  final String roomKey;
  final String roomName;
  final List<Map<String, dynamic>> items;
  final IconData Function(String) iconForAppliance;
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final String? homeId;

  const RoomDetailScreen({
    super.key,
    required this.roomKey,
    required this.roomName,
    required this.items,
    required this.iconForAppliance,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.homeId,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late List<Map<String, dynamic>> _items;
  bool _deleting = false;
    String _filter = 'all'; // all, warranty, attention, expired, none

  // "brand|product|tier" -> fetched provider list (avoids re-hitting the API).
  final Map<String, List<Map<String, dynamic>>> _serviceCache = {};

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Full-screen image, pinch-to-zoom.
  void _openImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => Padding(
                  padding: EdgeInsets.all(24),
                  child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint, size: 40),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------
  Future<void> _submitDeleteProduct(String product) async {
    if (widget.homeId == null || _deleting) return;
    setState(() => _deleting = true);
    try {
      final response = await ApiClient.delete(
        ApiConfig.productDeleteUrl(widget.homeId!),
        body: {'roomName': widget.roomKey, 'product': product},
      );
      debugPrint('🗑️ Delete product status: ${response.statusCode}');
      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() => _items.removeWhere((item) => item['product']?.toString() == product));
        _snack('$product removed ✅');
      } else {
        final data = jsonDecode(response.body);
        _snack(data['message']?.toString() ?? 'Could not remove appliance.');
      }
    } catch (e) {
      debugPrint('❌ Delete product error: $e');
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _confirmDeleteProduct(String product) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Remove appliance?',
      content: '$product will be removed from ${widget.roomName}.',
    );
    if (ok == true) _submitDeleteProduct(product);
  }

  // ---------------------------------------------------------------------
  // EDIT
  // ---------------------------------------------------------------------
  void _openEditDeviceDialog(Map<String, dynamic> item) {
    final deviceId = (item['deviceId'] ?? item['_id'])?.toString();
    if (deviceId == null) {
      _snack('This item has no deviceId, so it cannot be edited.');
      return;
    }

    final productController = TextEditingController(text: item['product']?.toString() ?? '');
    final brandController = TextEditingController(text: item['brand']?.toString() ?? '');
    final warrantyController = TextEditingController(text: item['warranty']?.toString() ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: AppDecor.dialogShape,
          title: const Text('Edit Appliance', style: AppText.dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDialogField(controller: productController, hint: 'Product name'),
              const SizedBox(height: 10),
              AppDialogField(controller: brandController, hint: 'Brand'),
              const SizedBox(height: 10),
              AppDialogField(controller: warrantyController, hint: 'Warranty (e.g. 2 Years)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: AppText.cancelAction),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final result = await EntityUpdateService.update(
                        homeId: widget.homeId,
                        deviceId: deviceId,
                        product: productController.text.trim().isNotEmpty
                            ? productController.text.trim()
                            : null,
                        brand: brandController.text.trim().isNotEmpty
                            ? brandController.text.trim()
                            : null,
                        warranty: warrantyController.text.trim().isNotEmpty
                            ? warrantyController.text.trim()
                            : null,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!mounted) return;
                      _snack(result['success'] == true
                          ? 'Appliance updated ✅'
                          : (result['message']?.toString() ?? 'Update failed'));
                      if (result['success'] == true) {
                        setState(() {
                          item['product'] = productController.text.trim();
                          item['brand'] = brandController.text.trim();
                          item['warranty'] = warrantyController.text.trim();
                        });
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                  : Text('Save', style: TextStyle(color: AppColors.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // WARRANTY HELPERS
  // ---------------------------------------------------------------------
  DateTime? _expiryOf(Map<String, dynamic> item) => WarrantyUtils.parseExpiry(
        item['warranty']?.toString(),
        referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
      );

  bool _isItemUnderWarranty(Map<String, dynamic> item) {
    final expiry = _expiryOf(item);
    return expiry != null && expiry.isAfter(DateTime.now());
  }
  bool _matchesFilter(Map<String, dynamic> item, String key) {
    final expiry = _expiryOf(item);
    final now = DateTime.now();
    switch (key) {
      case 'warranty':
        return expiry != null && expiry.isAfter(now);
      case 'attention':
        return expiry != null && expiry.difference(now).inDays <= 30; // expired + expiring soon
      case 'expired':
        return expiry != null && !expiry.isAfter(now);
      case 'none':
        return expiry == null;
      default:
        return true;
    }
  }

  int _countFor(String key) => _items.where((i) => _matchesFilter(i, key)).length;

  Widget _buildFilterBar() {
        const options = [
      {'key': 'all', 'label': 'All'},
      {'key': 'warranty', 'label': 'Warranty'},
      {'key': 'attention', 'label': 'Attention'},
      {'key': 'none', 'label': 'No warranty'},
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = options[i]['key']!;
          final selected = _filter == key;
          return ChoiceChip(
            label: Text('${options[i]['label']} ${_countFor(key)}'),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = key),
            backgroundColor: AppColors.cardBg,
            selectedColor: AppColors.primary,
            side: BorderSide(color: selected ? AppColors.primary : AppColors.borderMuted),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            ),
          );
        },
      ),
    );
  }
  // "8 months left", "Expired 12 days ago", or a fallback.

  // ---------------------------------------------------------------------
  // NEARBY PROVIDERS / BOOKING
  // ---------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _fetchNearbyProviders(
    Map<String, dynamic> item,
    bool isUnderWarranty,
  ) async {
    final brand = item['brand']?.toString() ?? '';
    final product = item['product']?.toString() ?? '';
    final cacheKey = '$brand|$product|$isUnderWarranty'.toLowerCase();
    if (_serviceCache.containsKey(cacheKey)) return _serviceCache[cacheKey]!;

    try {
      final response = await ApiClient.post(ApiConfig.nearbyServiceUrl, body: {
        'brand': brand,
        'product': product,
        'pincode': widget.pincode,
        'isUnderWarranty': isUnderWarranty,
      });
      debugPrint('🛠️ Nearby service status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          final list = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _serviceCache[cacheKey] = list;
          return list;
        }
      }
    } catch (e) {
      debugPrint('❌ Nearby service fetch error: $e');
    }
    return [];
  }

  Future<void> _callNumber(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (e) {
      debugPrint('Call launch error: $e');
      _snack('Could not start call.');
    }
  }

  Future<void> _openMapDirections(String address) async {
    final query = Uri.encodeComponent(address);
    try {
      await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Directions launch error: $e');
      _snack('Could not open maps.');
    }
  }

  // POST /createServiceTicket
  Future<bool> _submitServiceTicket({
    required Map<String, dynamic> provider,
    required Map<String, dynamic> item,
    required bool isUnderWarranty,
    String? availableTime,
  }) async {
    final providerMobile = (provider['mobile'] ?? provider['phone'])?.toString();
    if (providerMobile == null || providerMobile.isEmpty || providerMobile == 'N/A') {
      _snack('This provider has no contact number on file.');
      return false;
    }

    final product = item['product']?.toString() ?? 'Appliance';
    final brand = item['brand']?.toString() ?? '';
    final label = brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
    final warrantyNote = isUnderWarranty ? 'Under warranty' : 'Out of warranty';

    try {
      final response = await ApiClient.post(ApiConfig.createServiceTicketUrl, body: {
        'customerName': widget.name.isNotEmpty ? widget.name : 'Customer',
        'cust_number': ApiConfig.stripCountryCode(widget.mobileNumber),
        'address': widget.address,
        'description': '$label — $warrantyNote. Room: ${widget.roomName}.',
        'providerMobile': providerMobile,
        if (availableTime != null && availableTime.trim().isNotEmpty)
          'availableTime': availableTime.trim(),
      });
      debugPrint('🎫 Create ticket status: ${response.statusCode}');
      if (!mounted) return false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _snack('Service booked ✅ — the provider will reach out shortly.');
        return true;
      }
      final data = jsonDecode(response.body);
      _snack(data['message']?.toString() ?? 'Could not book this provider.');
      return false;
    } catch (e) {
      debugPrint('❌ Create ticket error: $e');
      _snack('Network error. Try again.');
      return false;
    }
  }

  void _openBookingDialog(Map<String, dynamic> provider, Map<String, dynamic> item, bool isUnderWarranty) {
    final timeController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: AppDecor.dialogShape,
              title: const Text('Confirm booking', style: AppText.dialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider['name'] ?? 'Provider'} will be notified about your ${item['product'] ?? 'appliance'}.',
                    style: AppText.faintCaption,
                  ),
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
                  child: const Text('Cancel', style: AppText.cancelAction),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final ok = await _submitServiceTicket(
                            provider: provider,
                            item: item,
                            isUnderWarranty: isUnderWarranty,
                            availableTime: timeController.text,
                          );
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (ok && mounted) Navigator.pop(context); // close provider sheet too
                        },
                  child: isSubmitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2),
                        )
                      : Text('Book', style: TextStyle(color: AppColors.onPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

 void _openServiceBookingSheet(Map<String, dynamic> item) {
  final isUnderWarranty = _isItemUnderWarranty(item);
  final product = item['product']?.toString() ?? 'Appliance';
  final accent = isUnderWarranty ? AppColors.success : AppColors.danger;

  final providersFuture = _fetchNearbyProviders(item, isUnderWarranty)
      .timeout(const Duration(seconds: 30), onTimeout: () => <Map<String, dynamic>>[]);

  showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
          builder: (sheetContext) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: providersFuture,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
            final providers = snapshot.data ?? [];

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isUnderWarranty ? Icons.shield_outlined : Icons.build_rounded,
                          color: accent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUnderWarranty ? 'Authorized service centers' : 'Local repair providers',
                              style: AppText.dialogTitle,
                            ),
                            const SizedBox(height: 2),
                            Text('$product · Pincode ${widget.pincode}', style: AppText.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (providers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No service providers found nearby.', style: AppText.faintCaption),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: providers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
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
                                name: p['name']?.toString() ?? 'Not available',
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
                                                            if (!isUnderWarranty) ...[
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                                                  child: ElevatedButton.icon(
                                  onPressed: hasPhone
                                      ? () => _openBookingDialog(p, item, isUnderWarranty)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.onPrimary,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.onPrimary),
                                  label: Text('Book this provider',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.onPrimary)),
                                ),
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

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  Widget _buildItemCard(Map<String, dynamic> item) {
    final product = item['product']?.toString() ?? 'Unknown';
    final brand = item['brand']?.toString() ?? 'N/A';
    final photoUrl = item['imageUrl']?.toString();
    final warrantyCardUrl = item['warrantyCardUrl']?.toString();

    final expiry = _expiryOf(item);
final isUnknown = expiry == null;
final isUnderWarranty = _isItemUnderWarranty(item);
final accent = isUnknown
    ? AppColors.textMuted
    : (isUnderWarranty ? AppColors.success : AppColors.danger);
final statusIcon = isUnknown
    ? Icons.help_outline_rounded
    : (isUnderWarranty ? Icons.verified_rounded : Icons.error_rounded);
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
            decoration: AppDecor.flatCard(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail + small status badge
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: hasPhoto ? () => _openImagePreview(context, photoUrl) : null,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: hasPhoto
                                ? Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Icon(widget.iconForAppliance(product), color: accent, size: 26),
                                  )
                                : Icon(widget.iconForAppliance(product), color: accent, size: 26),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.cardBg, width: 2),
                            ),
                            child: Icon(statusIcon, size: 11, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _openEditDeviceDialog(item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(product,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ),
                                _buildItemMenu(item, product),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(brand,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                WarrantyBadge(expiry: expiry),
                                if (warrantyCardUrl != null && warrantyCardUrl.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _openImagePreview(context, warrantyCardUrl),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.primaryBorder, width: 1),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.network(
                                        warrantyCardUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.receipt_long,
                                            size: 12, color: AppColors.textFaint),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.borderSubtle, height: 1),
                const SizedBox(height: 12),
                // Solid for expired, outlined for healthy.
                                                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openServiceBookingSheet(item),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(
                      isUnderWarranty ? Icons.shield_outlined : Icons.build_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      isUnderWarranty ? 'Book authorized service' : 'Find repair near you',
                      style: TextStyle(
                          color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemMenu(Map<String, dynamic> item, String product) {
    PopupMenuItem<String> entry(String value, IconData icon, Color iconColor, String text, Color textColor) {
      return PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: textColor)),
        ]),
      );
    }

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 18),
      color: AppColors.cardBg,
      onSelected: (value) {
        if (value == 'edit') _openEditDeviceDialog(item);
        if (value == 'service') _openServiceBookingSheet(item);
        if (value == 'delete' && !_deleting) _confirmDeleteProduct(product);
      },
      itemBuilder: (context) => [
        entry('edit', Icons.edit_outlined, AppColors.primary, 'Edit', AppColors.textPrimary),
        entry('service', Icons.build_rounded, AppColors.primary, 'Find service', AppColors.textPrimary),
        entry('delete', Icons.delete_outline, AppColors.danger, 'Remove', AppColors.danger),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
        final visible = _items.where((i) => _matchesFilter(i, _filter)).toList();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text(widget.roomName, style: TextStyle(color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
                backgroundColor: AppColors.cardBg,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScanTab(
                mobileNumber: widget.mobileNumber,
                address: widget.address,
                pincode: widget.pincode,
                name: widget.name,
                homeId: widget.homeId,
                initialRoom: widget.roomName,
                lockRoom: true,
                onBack: () => Navigator.pop(context),
              ),
            ),
          );
        },
                icon: Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 15),
                label: Text('Add appliance',
            style: TextStyle(
                color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
            body: _items.isEmpty
          ? Center(
              child: Text('No appliances in this room yet.\nScan one and pick this room.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            )
          : Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text('No devices in this filter',
                              style: TextStyle(color: AppColors.textMuted)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _buildItemCard(visible[index]),
                        ),
                ),
              ],
            ),
    );
  }
}