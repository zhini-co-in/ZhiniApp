// lib/devices_tab.dart
//
// "My Devices" screen — search + filters + status-grouped device list.
// Reuses the same Hive box ('homes') that HomeTab populates, so no extra
// network fetch is needed here; this screen is purely a different view
// over the same data HomeTab already keeps in sync.
//
// Details sheet / edit / service / booking / remove all live in
// widgets/device_details_sheet.dart (shared with HomeTab).

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'constants/app_strings.dart';
import 'home_tab.dart' show ScanRequest;
import 'models/home_model.dart';
import 'theme/app_theme.dart';
import 'utils/devices_filter_bus.dart';
import 'widgets/device_details_sheet.dart';

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

typedef _DeviceEntry = DeviceEntry;

class _DevicesTabState extends State<DevicesTab> {
  final _homeBox = Hive.box<HomeModel>('homes');
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _query = '';
  String _activeTab = 'All'; // All, Warranty, Attention, Expired, Service
  final Set<String> _quickFilters = {}; // 'expired','service','healthy'
  String? _roomFilter;
  final List<String> _recentSearches = [];

  // Id of the home currently shown (set in build). Used by the scan buttons
  // so new devices are added to THIS home instead of creating a new one.
  String? _currentHomeIdCache;

  static const List<Map<String, String>> _categories = [
    {'label': AppStrings.catAc, 'key': 'ac'},
    {'label': AppStrings.catFridge, 'key': 'fridge|refrigerator'},
    {'label': AppStrings.catWashingMachine, 'key': 'washing machine'},
    {'label': AppStrings.catTv, 'key': 'tv|television'},
    {'label': AppStrings.catFan, 'key': 'fan'},
  ];
  String? _categoryFilter;

  bool get _searchActive => _searchFocus.hasFocus || _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
    devicesFilterRequest.addListener(_onFilterRequest);
    _consumeFilterRequest(initial: true); // request came before this tab was created
  }

  void _onFilterRequest() => _consumeFilterRequest();

  void _consumeFilterRequest({bool initial = false}) {
    final f = devicesFilterRequest.value;
    if (f == null) return;
    devicesFilterRequest.value = null; // consume

    void apply() {
      _activeTab = f;
      _quickFilters.clear();
      _roomFilter = null;
      _categoryFilter = null;
      _clearAdvanced();
    }

    if (initial) {
      apply();
    } else {
      _searchController.clear();
      _searchFocus.unfocus();
      if (mounted) setState(apply);
    }
  }

  @override
  void dispose() {
    devicesFilterRequest.removeListener(_onFilterRequest);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // DATA
  // -----------------------------------------------------------------
  Map<String, dynamic>? _findCurrentHome(List<HomeModel> homes) {
    if (homes.isEmpty) return null;
    final maps = homes.map((h) => h.toMap()).toList();

    for (final map in maps) {
      final addr = map['address']?.toString() ?? '';
      if (addr.isNotEmpty && widget.address.isNotEmpty && addr == widget.address) {
        return map;
      }
    }
    // Fallback: first registered home — skip the "Default" placeholder.
    for (final map in maps) {
      final addr = map['address']?.toString().trim().toLowerCase() ?? '';
      if (addr != 'default') return map;
    }
    return maps.first;
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
      case 'Attention':
        return e.isAttention;
      case 'Expired':
        return e.isExpired;
      case 'No warranty':
        return e.warrantyUnknown;
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
        .where(_matchesAdvanced)
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
  String _brandLabel(_DeviceEntry e) {
    final b = e.brand.trim();
    final valid = b.isNotEmpty && b.toLowerCase() != 'unknown' && b.toUpperCase() != 'N/A';
    return valid ? b : AppStrings.brandNotAdded;
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  void _openDetailsSheet(_DeviceEntry e) => showDeviceDetailsSheet(
        context,
        e,
        mobileNumber: widget.mobileNumber,
        name: widget.name,
        onChanged: _refreshView,
      );

  void _requestScan() {
    widget.onScanTap?.call(
      homeId: _currentHomeIdCache,
      address: widget.address,
      pincode: widget.pincode,
    );
  }

  // Three-dot popup menu shown on every device card.
  Widget _buildItemMenu(_DeviceEntry e) {
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

    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 18),
        color: AppColors.cardBg,
        onSelected: (value) {
          if (value == 'edit') showDeviceEditDialog(context, e, onChanged: _refreshView);
          if (value == 'service') {
            showDeviceServiceSheet(context, e,
                mobileNumber: widget.mobileNumber, name: widget.name);
          }
          if (value == 'delete') confirmRemoveDevice(context, e, onChanged: _refreshView);
        },
        itemBuilder: (context) => [
          entry('edit', Icons.edit_outlined, AppColors.primary, AppStrings.edit, AppColors.textPrimary),
          entry('service', Icons.build_rounded, AppColors.primary, AppStrings.findService,
              AppColors.textPrimary),
          entry('delete', Icons.delete_outline, AppColors.danger, AppStrings.remove, AppColors.danger),
        ],
      ),
    );
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
        _currentHomeIdCache = home?['id']?.toString();
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
                  child: Row(
                    children: [
                      Expanded(child: _buildSearchBar()),
                      const SizedBox(width: 10),
                      _buildFilterButton(allDevices),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: _searchActive
                        ? _buildSearchMode(allDevices, filtered)
                        : (_advancedActive
                            ? _buildFilteredView(allDevices, filtered)
                            : _buildDashboard(allDevices)),
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
              const Text(AppStrings.myDevices,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(AppStrings.citySummary(city, total), style: AppText.caption),
            ],
          ),
        ),
        InkWell(
          onTap: _requestScan,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 15, color: AppColors.primary),
                SizedBox(width: 4),
                Text(AppStrings.scanNew, style: AppText.linkAction),
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
                hintText: AppStrings.searchApplianceHint,
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
        ],
      ),
    );
  }

  // ---------------- ADVANCED FILTER (Amazon / Flipkart style) ----------------
  // Multi-select. OR inside one group, AND between groups.
  final Set<String> _fStatus = {};
  final Set<String> _fCategories = {};
  final Set<String> _fBrands = {};

  int get _advancedCount => _fStatus.length + _fCategories.length + _fBrands.length;
  bool get _advancedActive => _advancedCount > 0;

  void _clearAdvanced() {
    _fStatus.clear();
    _fCategories.clear();
    _fBrands.clear();
  }

  static const List<Map<String, String>> _statusOptions = [
    {'key': 'active', 'label': 'Under warranty'},
    {'key': 'expiring', 'label': 'Expiring in 30 days'},
    {'key': 'expired', 'label': 'Warranty expired'},
    {'key': 'unknown', 'label': 'Warranty unknown'},
    {'key': 'service', 'label': 'Service due'},
  ];

  bool _statusMatch(_DeviceEntry e, String key) {
    switch (key) {
      case 'active':
        return e.isUnderWarranty;
      case 'expiring':
        return e.isUnderWarranty && e.expiry!.difference(DateTime.now()).inDays <= 30;
      case 'expired':
        return e.isExpired;
      case 'unknown':
        return e.warrantyUnknown;
      case 'service':
        return e.isServiceDue;
    }
    return false;
  }

  bool _matchesAdvancedWith(
    _DeviceEntry e,
    Set<String> status,
    Set<String> cats,
    Set<String> brands,
  ) {
    if (status.isNotEmpty && !status.any((k) => _statusMatch(e, k))) return false;
    if (cats.isNotEmpty) {
      final text = e.product.toLowerCase();
      if (!cats.any((c) => c.split('|').any((k) => text.contains(k)))) return false;
    }
    if (brands.isNotEmpty && !brands.contains(e.brand.trim().toLowerCase())) return false;
    return true;
  }

  bool _matchesAdvanced(_DeviceEntry e) =>
      _matchesAdvancedWith(e, _fStatus, _fCategories, _fBrands);

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Map<String, String> _brandMap(List<_DeviceEntry> all) {
    final map = <String, String>{};
    for (final e in all) {
      final b = e.brand.trim();
      if (b.isEmpty || b.toLowerCase() == 'unknown' || b.toUpperCase() == 'N/A') continue;
      map.putIfAbsent(b.toLowerCase(), () => b);
    }
    return map;
  }

  Widget _buildFilterButton(List<_DeviceEntry> all) {
    final count = _advancedCount;
    return InkWell(
      onTap: () => _openFilterSheet(all),
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: count > 0 ? AppColors.primarySoft : AppColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: count > 0 ? AppColors.primary : AppColors.borderSubtle),
            ),
            child: const Icon(Icons.tune_rounded, size: 20, color: AppColors.primary),
          ),
          if (count > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Text('$count',
                    style: const TextStyle(
                        color: AppColors.onPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  void _openFilterSheet(List<_DeviceEntry> all) {
    final status = {..._fStatus};
    final cats = {..._fCategories};
    final brands = {..._fBrands};
    String section = 'status';

    final brandMap = _brandMap(all);
    final brandKeys = brandMap.keys.toList()..sort();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final resultCount =
              all.where((e) => _matchesAdvancedWith(e, status, cats, brands)).length;

          final sections = <Map<String, dynamic>>[
            {'key': 'status', 'label': 'Warranty', 'n': status.length},
            {'key': 'category', 'label': 'Appliance', 'n': cats.length},
            {'key': 'brand', 'label': 'Brand', 'n': brands.length},
          ];

          final Set<String> selected;
          final List<MapEntry<String, String>> opts;
          final int Function(String) countFor;
          switch (section) {
            case 'status':
              selected = status;
              opts = _statusOptions.map((o) => MapEntry(o['key']!, o['label']!)).toList();
              countFor = (k) => all.where((e) => _statusMatch(e, k)).length;
              break;
            case 'category':
              selected = cats;
              opts = _categories.map((c) => MapEntry(c['key']!, c['label']!)).toList();
              countFor = (k) => all.where((e) {
                    final t = e.product.toLowerCase();
                    return k.split('|').any((x) => t.contains(x));
                  }).length;
              break;
            default:
              selected = brands;
              opts = brandKeys.map((b) => MapEntry(b, brandMap[b]!)).toList();
              countFor = (k) => all.where((e) => e.brand.trim().toLowerCase() == k).length;
          }

          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                  child: Row(
                    children: [
                      const Text('Filters', style: AppText.dialogTitle),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderSubtle),
                Expanded(
                  child: Row(
                    children: [
                      // LEFT: filter groups
                      Container(
                        width: 118,
                        color: AppColors.scaffoldBg,
                        child: ListView(
                          children: sections.map((s) {
                            final isSel = section == s['key'];
                            final n = s['n'] as int;
                            return InkWell(
                              onTap: () => setSheet(() => section = s['key'] as String),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                decoration: BoxDecoration(
                                  color: isSel ? AppColors.cardBg : Colors.transparent,
                                  border: Border(
                                    left: BorderSide(
                                      color: isSel ? AppColors.primary : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s['label'] as String,
                                        style: TextStyle(
                                          color: isSel ? AppColors.primary : AppColors.textSecondary,
                                          fontSize: 13,
                                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (n > 0)
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: const BoxDecoration(
                                            color: AppColors.primary, shape: BoxShape.circle),
                                        child: Text('$n',
                                            style: const TextStyle(
                                                color: AppColors.onPrimary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      // RIGHT: options with checkboxes
                      Expanded(
                        child: opts.isEmpty
                            ? const Center(
                                child: Text('No options available', style: AppText.faintCaption))
                            : ListView(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                children: opts.map((o) {
                                  final checked = selected.contains(o.key);
                                  return InkWell(
                                    onTap: () => setSheet(() {
                                      if (!selected.remove(o.key)) selected.add(o.key);
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: checked,
                                            activeColor: AppColors.primary,
                                            checkColor: AppColors.onPrimary,
                                            visualDensity: VisualDensity.compact,
                                            onChanged: (_) => setSheet(() {
                                              if (!selected.remove(o.key)) selected.add(o.key);
                                            }),
                                          ),
                                          Expanded(
                                            child: Text(o.value,
                                                style: const TextStyle(
                                                    color: AppColors.textPrimary, fontSize: 13.5)),
                                          ),
                                          Text('${countFor(o.key)}', style: AppText.caption),
                                          const SizedBox(width: 8),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderSubtle),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setSheet(() {
                              status.clear();
                              cats.clear();
                              brands.clear();
                            }),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.borderSubtle),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Clear all',
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _fStatus
                                  ..clear()
                                  ..addAll(status);
                                _fCategories
                                  ..clear()
                                  ..addAll(cats);
                                _fBrands
                                  ..clear()
                                  ..addAll(brands);
                              });
                              Navigator.pop(sheetContext);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Show $resultCount device${resultCount == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    color: AppColors.onPrimary, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Removable chips for the currently applied filters.
  Widget _buildActiveFilterChips(List<_DeviceEntry> all) {
    final brandMap = _brandMap(all);

    Widget chip(String label, VoidCallback onRemove) {
      return InkWell(
        onTap: () => setState(onRemove),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 12.5)),
              const SizedBox(width: 6),
              const Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
            ],
          ),
        ),
      );
    }

    final chips = <Widget>[
      for (final k in _fStatus.toList())
        chip(_statusOptions.firstWhere((o) => o['key'] == k)['label']!, () => _fStatus.remove(k)),
      for (final k in _fCategories.toList())
        chip(_categories.firstWhere((c) => c['key'] == k)['label']!, () => _fCategories.remove(k)),
      for (final k in _fBrands.toList()) chip(brandMap[k] ?? _cap(k), () => _fBrands.remove(k)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips,
        InkWell(
          onTap: () => setState(_clearAdvanced),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text('Clear all', style: AppText.linkAction),
          ),
        ),
      ],
    );
  }

  // Shown on the Devices screen when filters are applied (no search text).
  Widget _buildFilteredView(List<_DeviceEntry> all, List<_DeviceEntry> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActiveFilterChips(all),
        const SizedBox(height: 14),
        Text('${filtered.length} DEVICE${filtered.length == 1 ? '' : 'S'}',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 12),
        ..._buildResultsList(filtered),
      ],
    );
  }

  // ---------------- SEARCH MODE ----------------
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
            const Text(AppStrings.recentSearches,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: _recentSearches.map(_recentChip).toList()),
            const SizedBox(height: 20),
          ],
          const Text(AppStrings.browseByCategory,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: _categories.map(_categoryChip).toList()),
          if (_quickFilters.isNotEmpty || _categoryFilter != null || _roomFilter != null || _advancedActive) ...[
            const SizedBox(height: 20),
            ..._buildResultsList(filtered),
          ],
        ] else
          ..._buildResultsList(filtered, showHeader: true),
      ],
    );
  }

  Widget _buildTabsRow() {
    const tabs = ['All', 'Warranty', 'Attention', 'No warranty'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = tabs[i];
          final selected = _activeTab == t;
          return _dashPill(t, selected, () => setState(() => _activeTab = t));
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
        const Text(AppStrings.quickFilters,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(AppStrings.filterExpiredWarranty, Icons.error_outline_rounded, _quickFilters.contains('expired'), () {
              setState(() {
                if (!_quickFilters.remove('expired')) _quickFilters.add('expired');
              });
            }),
            chip(AppStrings.filterServiceDue, Icons.build_outlined, _quickFilters.contains('service'), () {
              setState(() {
                if (!_quickFilters.remove('service')) _quickFilters.add('service');
              });
            }),
            chip(AppStrings.filterByRoom, Icons.door_front_door_outlined, _roomFilter != null, () => _openRoomPicker(rooms)),
            chip(AppStrings.filterHealthy, Icons.check_circle_outline_rounded, _quickFilters.contains('healthy'), () {
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
              const Text(AppStrings.filterByRoomTitle, style: AppText.dialogTitle),
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
        Text(AppStrings.resultsFor(results.length, _query.trim()),
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 12),
      ],
      ...results.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildResultCard(e),
          )),
    ];
  }

  // Search-result card: tap -> details sheet, three-dot menu for quick actions.
  Widget _buildResultCard(_DeviceEntry e) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetailsSheet(e),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
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
                  Text(e.product,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_brandLabel(e),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  const SizedBox(height: 6),
                                    _warrantyIndicator(e),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildItemMenu(e),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    final q = _query.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 14),
            const Text(AppStrings.noApplianceFound,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              q.isNotEmpty ? AppStrings.notRegisteredYet(q) : AppStrings.tryDifferentSearch,
              textAlign: TextAlign.center,
              style: AppText.faintCaption,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- DASHBOARD MODE ----------------
  Widget _buildDashboard(List<_DeviceEntry> all) {
    final warrantyOk = all.where((e) => e.isUnderWarranty).length;
    final attentionCount = all.where((e) => e.isAttention).length;
    final noWarrantyCount = all.where((e) => e.warrantyUnknown).length;

    // List follows the active pill
    final visible = all.where(_matchesTab).toList();
    final attention = visible.where((e) => e.isAttention).toList();
    final serviceDue = visible.where((e) => e.isServiceDue && !e.isAttention).toList();
    final healthy = visible.where((e) => !e.isAttention && !e.isServiceDue).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _dashPill(AppStrings.pillAll(all.length), _activeTab == 'All', () => setState(() => _activeTab = 'All')),
              const SizedBox(width: 8),
              _dashPill(AppStrings.pillAttention(attentionCount), _activeTab == 'Attention',
                  () => setState(() => _activeTab = 'Attention')),
              const SizedBox(width: 8),
              _dashPill(AppStrings.pillWarranty(warrantyOk), _activeTab == 'Warranty',
                  () => setState(() => _activeTab = 'Warranty')),
              const SizedBox(width: 8),
              _dashPill('No warranty $noWarrantyCount', _activeTab == 'No warranty',
                  () => setState(() => _activeTab = 'No warranty')),
            ],
          ),
        ),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader(AppStrings.needsAttention),
          const SizedBox(height: 10),
          ...attention.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'attention'))),
        ],
        if (serviceDue.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader(AppStrings.serviceDueHeader),
          const SizedBox(height: 10),
          ...serviceDue.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'service'))),
        ],
        if (healthy.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeader(_activeTab == 'No warranty' ? 'NO WARRANTY DEVICES' : AppStrings.healthyDevices),
          const SizedBox(height: 10),
          ...healthy.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10), child: _buildDashCard(e, 'healthy'))),
        ],
        if (all.isEmpty) ...[
          const SizedBox(height: 40),
          const Center(
            child: Column(
              children: [
                Icon(Icons.devices_other_rounded, size: 40, color: AppColors.textFaint),
                SizedBox(height: 10),
                Text(AppStrings.noAppliancesYet, style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ] else if (visible.isEmpty) ...[
          const SizedBox(height: 40),
          const Center(child: Text(AppStrings.noDevicesInFilter, style: TextStyle(color: AppColors.textMuted))),
        ],
      ],
    );
  }

  Widget _dashPill(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : AppColors.borderMuted),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title,
        style: const TextStyle(
            color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8));
  }

  // Dashboard card: tap -> details sheet, three-dot menu for quick actions.
  Widget _buildDashCard(_DeviceEntry e, String variant) {
    final List<Widget> badges = variant == 'service'
        ? [_pill(AppStrings.filterServiceDue, AppColors.warning), _warrantyIndicator(e)]
        : [_warrantyIndicator(e)];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetailsSheet(e),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
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
                  Text(e.product,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_brandLabel(e),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  const SizedBox(height: 6),
                                    Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildItemMenu(e),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Shared indicator (No warranty -> red, active -> green, expired -> badge).
  Widget _warrantyIndicator(_DeviceEntry e) => DeviceWarrantyIndicator(e);

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