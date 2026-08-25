// lib/devices_tab.dart
//
// "My Devices" screen — search + filters + status-grouped device list.
// Reuses the same Hive box ('homes') that HomeTab populates, so no extra
// network fetch is needed here; this screen is purely a different view
// over the same data HomeTab already keeps in sync.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'constants/api_config.dart';
import 'models/home_model.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'services/entity_update_service.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/confirm_action_dialog.dart';
import 'widgets/service_provider_card.dart';
import 'home_tab.dart' show ScanRequest;
import 'package:url_launcher/url_launcher.dart';

class DevicesTab extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final ScanRequest? onScanTap;

  const DevicesTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.onScanTap,
  });

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

// Flattened view of one appliance + which home/room it lives in.
class _DeviceEntry {
  final String? homeId;
  final String homeAddress;
  final String pincode;
  final String roomKey;
  final String roomName;
  final Map<String, dynamic> raw;

  _DeviceEntry({
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

  DateTime? get _createdAt => DateTime.tryParse(raw['createdAt']?.toString() ?? '');

  DateTime? get expiry =>
      WarrantyUtils.parseExpiry(raw['warranty']?.toString(), referenceDate: _createdAt);

  bool get isUnderWarranty => expiry != null && expiry!.isAfter(DateTime.now());
  bool get isExpired => expiry != null && !expiry!.isAfter(DateTime.now());
  bool get warrantyUnknown => expiry == null;

  // Backend may optionally send `lastServiceDate` / `nextServiceDue` /
  // `serviceDue`. If none of those are present we simply don't flag the
  // device as service-due instead of guessing.
  bool get isServiceDue {
    if (raw['serviceDue'] == true) return true;
    final nextDue = DateTime.tryParse(raw['nextServiceDue']?.toString() ?? '');
    if (nextDue != null) return !nextDue.isAfter(DateTime.now());
    return false;
  }

  int get ageYears {
    final created = _createdAt;
    if (created == null) return 0;
    return (DateTime.now().difference(created).inDays / 365).floor();
  }

  String get ageLabel {
    final created = _createdAt;
    if (created == null) return '';
    final days = DateTime.now().difference(created).inDays;
    if (days < 30) return '$days d';
    final years = days / 365;
    if (years < 1) return '${(days / 30).round()} mo';
    return '${years.toStringAsFixed(years >= 10 ? 0 : 1)} yrs';
  }

  String get purchasedYear => _createdAt != null ? _createdAt!.year.toString() : 'Unknown';
}

class _DevicesTabState extends State<DevicesTab> {
  final _homeBox = Hive.box<HomeModel>('homes');
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _query = '';
  String _activeTab = 'All'; // All, Warranty, Expired, Service
  final Set<String> _quickFilters = {}; // 'expired','service','healthy'
  String? _roomFilter;
  final List<String> _recentSearches = [];

  static const List<Map<String, String>> _categories = [
    {'label': 'AC', 'key': 'ac'},
    {'label': 'Fridge', 'key': 'fridge|refrigerator'},
    {'label': 'Wt. Machine', 'key': 'washing machine'},
    {'label': 'TV', 'key': 'tv|television'},
    {'label': 'Fan', 'key': 'fan'},
  ];
  String? _categoryFilter;

  bool get _searchActive => _searchFocus.hasFocus || _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // DATA
  // -----------------------------------------------------------------
  Map<String, dynamic>? _findCurrentHome(List<HomeModel> homes) {
    if (homes.isEmpty) return null;
    for (final h in homes) {
      final map = h.toMap();
      final addr = map['address']?.toString() ?? '';
      if (addr.isNotEmpty && widget.address.isNotEmpty && addr == widget.address) {
        return map;
      }
    }
    return homes.first.toMap();
  }

  List<_DeviceEntry> _flatten(Map<String, dynamic>? home) {
    if (home == null) return [];
    final rooms = (home['rooms'] as Map?) ?? {};
    final entries = <_DeviceEntry>[];
    rooms.forEach((key, value) {
      if (value is! List) return;
      for (final item in value) {
        final map = Map<String, dynamic>.from(item as Map);
        final roomKey = key.toString();
        entries.add(_DeviceEntry(
          homeId: home['id']?.toString(),
          homeAddress: home['address']?.toString() ?? widget.address,
          pincode: home['pincode']?.toString() ?? widget.pincode,
          roomKey: roomKey,
          roomName: roomKey.isNotEmpty ? '${roomKey[0].toUpperCase()}${roomKey.substring(1)}' : roomKey,
          raw: map,
        ));
      }
    });
    return entries;
  }

  // -----------------------------------------------------------------
  // FILTERING
  // -----------------------------------------------------------------
  bool _matchesCategory(_DeviceEntry e) {
    if (_categoryFilter == null) return true;
    final text = e.product.toLowerCase();
    return _categoryFilter!.split('|').any((k) => text.contains(k));
  }

  bool _matchesTab(_DeviceEntry e) {
    switch (_activeTab) {
      case 'Warranty':
        return e.isUnderWarranty;
      case 'Expired':
        return e.isExpired;
      case 'Service':
        return e.isServiceDue;
      default:
        return true;
    }
  }

  bool _matchesQuickFilters(_DeviceEntry e) {
    if (_quickFilters.contains('expired') && !e.isExpired) return false;
    if (_quickFilters.contains('service') && !e.isServiceDue) return false;
    if (_quickFilters.contains('healthy') && !(e.isUnderWarranty && !e.isServiceDue)) return false;
    if (_roomFilter != null && e.roomKey != _roomFilter) return false;
    return true;
  }

  bool _matchesQuery(_DeviceEntry e, String q) {
    if (q.trim().isEmpty) return true;
    final needle = q.trim().toLowerCase();
    return e.product.toLowerCase().contains(needle) ||
        e.brand.toLowerCase().contains(needle) ||
        e.roomName.toLowerCase().contains(needle);
  }

  List<_DeviceEntry> _applyAllFilters(List<_DeviceEntry> all) {
    return all
        .where(_matchesTab)
        .where(_matchesQuickFilters)
        .where(_matchesCategory)
        .where((e) => _matchesQuery(e, _query))
        .toList();
  }

  // -----------------------------------------------------------------
  // ACTIONS
  // -----------------------------------------------------------------
  void _submitSearch(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() {
      _recentSearches.remove(v);
      _recentSearches.insert(0, v);
      if (_recentSearches.length > 6) _recentSearches.removeLast();
    });
    _searchFocus.unfocus();
  }

  void _exitSearch() {
    _searchController.clear();
    _query = '';
    _categoryFilter = null;
    _quickFilters.clear();
    _roomFilter = null;
    _searchFocus.unfocus();
    setState(() {});
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> _openMapDirections(String address) async {
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyProviders(_DeviceEntry e) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.nearbyServiceUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'brand': e.brand,
          'product': e.product,
          'pincode': e.pincode,
          'isUnderWarranty': e.isUnderWarranty,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          return rawList.map((x) => Map<String, dynamic>.from(x as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('❌ Nearby service fetch error: $e');
    }
    return [];
  }

  void _openServiceSheet(_DeviceEntry e) {
    final accent = e.isUnderWarranty ? AppColors.success : AppColors.danger;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchNearbyProviders(e),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final providers = snapshot.data ?? [];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.isUnderWarranty ? 'Authorized service centers' : 'Local repair providers',
                      style: AppText.dialogTitle),
                  const SizedBox(height: 2),
                  Text('${e.product} · Pincode ${e.pincode}', style: AppText.caption),
                  const SizedBox(height: 16),
                  if (loading)
                    const Padding(
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
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = providers[i];
                          final phone = (p['mobile'] ?? p['phone'])?.toString();
                          final address = p['address']?.toString();
                          final ratingRaw = p['rating'];
                          final rating = ratingRaw != null && ratingRaw.toString() != 'N/A'
                              ? double.tryParse(ratingRaw.toString())
                              : null;
                          return ServiceProviderCard(
                            name: p['name']?.toString() ?? 'Not available',
                            address: address,
                            phone: phone,
                            rating: rating,
                            onCall: (phone != null && phone.isNotEmpty && phone != 'N/A')
                                ? () => _callNumber(phone)
                                : null,
                            onDirections:
                                (address != null && address.isNotEmpty && address != 'Address not available')
                                    ? () => _openMapDirections(address)
                                    : null,
                          );
                        },
                      ),
                    ),
                  Text('$accent', style: const TextStyle(fontSize: 0)), // keep accent referenced
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _bookAllForResults(List<_DeviceEntry> results) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Requesting service for ${results.length} appliance${results.length == 1 ? '' : 's'}…')),
    );
  }

  void _openDeviceActions(_DeviceEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
                title: const Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openEditDialog(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.build_rounded, color: AppColors.primary),
                title: const Text('Find service', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openServiceSheet(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmRemove(e);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openEditDialog(_DeviceEntry e) {
    if (e.deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item has no deviceId, cannot edit.')),
      );
      return;
    }
    final productController = TextEditingController(text: e.product);
    final brandController = TextEditingController(text: e.brand);
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final result = await EntityUpdateService.update(
                        deviceId: e.deviceId,
                        product: productController.text.trim().isNotEmpty ? productController.text.trim() : null,
                        brand: brandController.text.trim().isNotEmpty ? brandController.text.trim() : null,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(result['success'] == true
                                ? 'Appliance updated ✅'
                                : (result['message']?.toString() ?? 'Update failed'))),
                      );
                      if (result['success'] == true) {
                        setState(() {
                          e.raw['product'] = productController.text.trim();
                          e.raw['brand'] = brandController.text.trim();
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(_DeviceEntry e) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Remove appliance?',
      content: '${e.product} will be removed from ${e.roomName}.',
    );
    if (ok != true || e.homeId == null) return;
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.productDeleteUrl(e.homeId!)),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'roomName': e.roomKey, 'product': e.product}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {}); // Hive box listener (below) will refresh once HomeTab re-fetches.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${e.product} removed ✅')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not remove appliance.')));
      }
    } catch (err) {
      debugPrint('❌ Delete device error: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
      }
    }
  }

  // -----------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<HomeModel>>(
      valueListenable: _homeBox.listenable(),
      builder: (context, box, _) {
        final home = _findCurrentHome(box.values.toList());
        final allDevices = _flatten(home);
        final filtered = _applyAllFilters(allDevices);
        final city = (home?['address']?.toString() ?? widget.address).split(',').first.trim();

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _buildHeader(city, allDevices.length),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSearchBar(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: _searchActive
                        ? _buildSearchMode(allDevices, filtered)
                        : _buildDashboard(allDevices, home),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String city, int total) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('My Devices',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('$city · $total registered', style: AppText.caption),
            ],
          ),
        ),
        InkWell(
          onTap: () => widget.onScanTap?.call(
            homeId: null,
            address: widget.address,
            pincode: widget.pincode,
          ),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 15, color: AppColors.primary),
                SizedBox(width: 4),
                Text('Scan new', style: AppText.linkAction),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          if (_searchActive)
            InkWell(
              onTap: _exitSearch,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.search, size: 18, color: AppColors.textMuted),
            ),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onSubmitted: _submitSearch,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search appliances, brand, room…',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              onTap: () => _searchController.clear(),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
              ),
            )
          else if (!_searchActive)
            InkWell(
              onTap: () => _searchFocus.requestFocus(),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- SEARCH MODE (Image 1) ----------------
  Widget _buildSearchMode(List<_DeviceEntry> all, List<_DeviceEntry> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _buildTabsRow(),
        const SizedBox(height: 16),
        if (_query.trim().isEmpty) ...[
          _buildQuickFilters(all),
          const SizedBox(height: 20),
          if (_recentSearches.isNotEmpty) ...[
            const Text('RECENT SEARCHES',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: _recentSearches.map(_recentChip).toList()),
            const SizedBox(height: 20),
          ],
          const Text('BROWSE BY CATEGORY',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: _categories.map(_categoryChip).toList()),
          if (_quickFilters.isNotEmpty || _categoryFilter != null || _roomFilter != null) ...[
            const SizedBox(height: 20),
            ..._buildResultsList(filtered),
          ],
        ] else
          ..._buildResultsList(filtered, showHeader: true),
      ],
    );
  }

  Widget _buildTabsRow() {
    const tabs = ['All', 'Warranty', 'Expired', 'Service'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = tabs[i];
          final selected = _activeTab == t;
          return ChoiceChip(
            label: Text(t),
            selected: selected,
            onSelected: (_) => setState(() => _activeTab = t),
            backgroundColor: AppColors.cardBg,
            selectedColor: AppColors.primary,
            labelStyle: selected ? AppText.chipSelected : AppText.chipUnselected,
            side: BorderSide(color: selected ? AppColors.primary : AppColors.borderMuted),
          );
        },
      ),
    );
  }

  Widget _buildQuickFilters(List<_DeviceEntry> all) {
    Widget chip(String label, IconData icon, bool active, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : AppColors.cardBgAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppColors.primary : AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: active ? AppColors.primary : AppColors.textSecondary, fontSize: 12.5)),
            ],
          ),
        ),
      );
    }

    final rooms = all.map((e) => e.roomKey).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('QUICK FILTERS',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('Expired warranty', Icons.error_outline_rounded, _quickFilters.contains('expired'), () {
              setState(() {
                if (!_quickFilters.remove('expired')) _quickFilters.add('expired');
              });
            }),
            chip('Service due', Icons.build_outlined, _quickFilters.contains('service'), () {
              setState(() {
                if (!_quickFilters.remove('service')) _quickFilters.add('service');
              });
            }),
            chip('By room', Icons.door_front_door_outlined, _roomFilter != null, () => _openRoomPicker(rooms)),
            chip('Healthy', Icons.check_circle_outline_rounded, _quickFilters.contains('healthy'), () {
              setState(() {
                if (!_quickFilters.remove('healthy')) _quickFilters.add('healthy');
              });
            }),
          ],
        ),
      ],
    );
  }

  void _openRoomPicker(List<String> rooms) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text('Filter by room', style: AppText.dialogTitle),
              const SizedBox(height: 8),
              ...rooms.map((r) => ListTile(
                    title: Text(r[0].toUpperCase() + r.substring(1), style: const TextStyle(color: AppColors.textPrimary)),
                    trailing: _roomFilter == r ? const Icon(Icons.check, color: AppColors.primary) : null,
                    onTap: () {
                      setState(() => _roomFilter = _roomFilter == r ? null : r);
                      Navigator.pop(sheetContext);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _recentChip(String label) {
    return InkWell(
      onTap: () {
        _searchController.text = label;
        _searchController.selection = TextSelection.collapsed(offset: label.length);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(Map<String, String> cat) {
    final active = _categoryFilter == cat['key'];
    return InkWell(
      onTap: () => setState(() => _categoryFilter = active ? null : cat['key']),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppColors.primary : AppColors.borderSubtle),
        ),
        child: Text(cat['label']!,
            style: TextStyle(color: active ? AppColors.primary : AppColors.textSecondary, fontSize: 12.5)),
      ),
    );
  }

  List<Widget> _buildResultsList(List<_DeviceEntry> results, {bool showHeader = false}) {
    if (results.isEmpty) {
      return [_buildNoResults()];
    }
    return [
      if (showHeader) ...[
        Text('${results.length} RESULT${results.length == 1 ? '' : 'S'} FOR "${_query.trim()}"',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 12),
      ],
      ...results.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildResultCard(e),
          )),
      if (results.length > 1) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _bookAllForResults(results),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.build_rounded, size: 15, color: AppColors.primary),
            label: Text('Book service for all ${results.length}',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ];
  }

  Widget _buildResultCard(_DeviceEntry e) {
    String badgeText;
    Color badgeColor;
    if (e.warrantyUnknown) {
      badgeText = 'Unregistered';
      badgeColor = AppColors.textMuted;
    } else if (e.isExpired) {
      final days = DateTime.now().difference(e.expiry!).inDays;
      badgeText = 'Warranty expired · $days d ago';
      badgeColor = AppColors.danger;
    } else {
      final daysLeft = e.expiry!.difference(DateTime.now()).inDays;
      if (daysLeft <= 30) {
        badgeText = 'Warranty expiring · $daysLeft days';
        badgeColor = AppColors.warning;
      } else {
        final years = (daysLeft / 365).toStringAsFixed(daysLeft >= 365 ? 0 : 1);
        badgeText = 'Warranty active · $years${daysLeft >= 365 ? 'yr' : ' yrs'}';
        badgeColor = AppColors.success;
      }
    }

    return InkWell(
      onTap: () => _openDeviceActions(e),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                  ? Image.network(e.imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.devices_other_rounded, color: AppColors.textFaint))
                  : const Icon(Icons.devices_other_rounded, color: AppColors.textFaint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.brand.isNotEmpty ? '${e.brand} ' : ''}${e.product}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${e.roomName} · ${e.purchasedYear}', style: AppText.caption),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    final q = _query.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 40, color: AppColors.textFaint),
          const SizedBox(height: 14),
          const Text('No appliance found', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            q.isNotEmpty ? '"$q" is not registered in your home yet.' : 'Try a different search or filter.',
            textAlign: TextAlign.center,
            style: AppText.faintCaption,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => widget.onScanTap?.call(
                homeId: null,
                address: widget.address,
                pincode: widget.pincode,
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppColors.primary),
              label: Text(q.isNotEmpty ? 'Scan and add $q' : 'Scan and add appliance',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Or try searching for:', style: AppText.faintCaption),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _suggestionChip('By room', Icons.door_front_door_outlined, () {}),
              _suggestionChip('By brand', Icons.sell_outlined, () {}),
              _suggestionChip('All devices', Icons.devices_other_rounded, _exitSearch),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  // ---------------- DASHBOARD MODE (Image 2) ----------------
  Widget _buildDashboard(List<_DeviceEntry> all, Map<String, dynamic>? home) {
    final warrantyOk = all.where((e) => e.isUnderWarranty).length;
    final attention = all.where((e) => e.isExpired || (!e.warrantyUnknown && e.expiry!.difference(DateTime.now()).inDays <= 30)).toList();
    final serviceDue = all.where((e) => e.isServiceDue && !attention.contains(e)).toList();
    final healthy = all.where((e) => !attention.contains(e) && !serviceDue.contains(e)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _dashPill('All ${all.length}', _activeTab == 'All', () => setState(() => _activeTab = 'All')),
              const SizedBox(width: 8),
              _dashPill('Attention ${attention.length}', false, () => setState(() {
                    _searchFocus.requestFocus();
                    _quickFilters
                      ..clear()
                      ..add('expired');
                  })),
              const SizedBox(width: 8),
              _dashPill('Warranty $warrantyOk', _activeTab == 'Warranty', () => setState(() => _activeTab = 'Warranty')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _statBox('${all.length}', 'Total', AppColors.textMuted),
            _statBox('$warrantyOk', 'Warranty', AppColors.success),
            _statBox('${attention.length}', 'Attention', AppColors.danger),
            _statBox('${serviceDue.length}', 'Svc due', AppColors.warning),
          ],
        ),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader('⚠ NEEDS ATTENTION'),
          const SizedBox(height: 10),
          ...attention.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'attention'))),
        ],
        if (serviceDue.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader('🔧 SERVICE DUE'),
          const SizedBox(height: 10),
          ...serviceDue.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'service'))),
        ],
        if (healthy.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader('✓ HEALTHY DEVICES'),
          const SizedBox(height: 10),
          ...healthy.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'healthy'))),
        ],
        if (all.isEmpty) ...[
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                const Icon(Icons.devices_other_rounded, size: 40, color: AppColors.textFaint),
                const SizedBox(height: 10),
                const Text('No appliances yet', style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => widget.onScanTap?.call(homeId: home?['id']?.toString(), address: widget.address, pincode: widget.pincode),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: BorderSide(color: AppColors.primaryBorder.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 18),
            label: const Text('Scan and add another appliance', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _dashPill(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: AppColors.cardBg,
      selectedColor: AppColors.primary,
      labelStyle: selected ? AppText.chipSelected : AppText.chipUnselected,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.borderMuted),
    );
  }

  Widget _statBox(String value, String label, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8));
  }

  Widget _buildDashCard(_DeviceEntry e, String variant) {
    Color accent;
    String rightLabel;
    IconData rightIcon;
    List<Widget> badges;

    switch (variant) {
      case 'attention':
        accent = e.isExpired ? AppColors.danger : AppColors.warning;
        rightLabel = e.ageLabel;
        rightIcon = e.isExpired ? Icons.build_rounded : Icons.shield_outlined;
        final days = e.isExpired ? DateTime.now().difference(e.expiry!).inDays : e.expiry!.difference(DateTime.now()).inDays;
        badges = [
          _pill(e.isExpired ? 'Warranty expired' : 'Expires in $days days', accent),
          const SizedBox(width: 6),
          _pill(e.isExpired ? '$days days ago' : '', AppColors.textMuted, plain: true),
        ];
        break;
      case 'service':
        accent = AppColors.warning;
        rightLabel = e.ageLabel;
        rightIcon = Icons.calendar_month_rounded;
        badges = [
          _pill('Service due', AppColors.warning),
          const SizedBox(width: 6),
          _pill(e.isUnderWarranty ? 'Warranty active' : 'Warranty expired', e.isUnderWarranty ? AppColors.success : AppColors.danger),
        ];
        break;
      default:
        accent = AppColors.success;
        rightLabel = e.ageLabel;
        rightIcon = Icons.chevron_right_rounded;
        badges = [
          _pill(e.warrantyUnknown ? 'No warranty data' : 'Warranty active', e.warrantyUnknown ? AppColors.textMuted : AppColors.success),
        ];
    }

    return InkWell(
      onTap: () => _openDeviceActions(e),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                  ? Image.network(e.imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.devices_other_rounded, color: accent))
                  : Icon(Icons.devices_other_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.product, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${e.roomName} · Purchased ${e.purchasedYear}', style: AppText.caption),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (rightLabel.isNotEmpty)
                  Text(rightLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => variant == 'healthy' ? _openDeviceActions(e) : _openServiceSheet(e),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(rightIcon, size: 14, color: accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, {bool plain = false}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: plain ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}