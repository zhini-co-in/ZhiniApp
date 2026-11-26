// lib/home_tab.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'constants/app_strings.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'address_screen.dart';
import 'constants/api_config.dart';
import 'models/home_model.dart';
import 'room_detail_screen.dart';
import 'services/api_client.dart';
import 'services/device_id_service.dart';
import 'services/entity_update_service.dart';
import 'services/home_services.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';
import 'theme/app_type.dart';
import 'utils/devices_filter_bus.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/device_details_sheet.dart';
import 'widgets/light_card.dart';
import 'widgets/section_header.dart';
import 'package:geolocator/geolocator.dart';
import 'theme/theme_controller.dart';
import 'dart:math' as math;
import 'device_details_screen.dart';
import 'utils/appliance_bus.dart';
import 'widgets/service_group_card.dart';
import 'widgets/service_group_sheet.dart';
import 'services/appliance_services_loader.dart';
import 'services/banner_loader.dart';
import 'widgets/zhini_logo.dart';

// Called whenever HomeTab wants the Scan tab to open. `homeId` is the home
// appliances should be attached to — pass null to make the backend create a
// BRAND NEW home from `address` (used by "Add Home"). Pass an existing
// home's id to add to that home.
// (knownRooms is kept only so other files that use this typedef still compile.)
typedef ScanRequest = void Function({
  String? homeId,
  required String address,
  required String pincode,
  List<String>? knownRooms,
});

class HomeTab extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
    final ValueChanged<String>? onNameChanged;
  final ScanRequest? onScanTap;
  final VoidCallback? onProfileTap;
  final ValueChanged<bool>? onHomeStatusChanged;
  final void Function(String? homeId, String address, String pincode)? onSelectedHomeChanged;
  final ValueChanged<String>? onOpenDevices; // 'All' | 'Warranty' | 'Attention'
  final VoidCallback? onOpenServices; // "See All" -> Service tab

  const HomeTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
     this.name = '',
    this.onNameChanged,
    this.onScanTap,
    this.onProfileTap,
    this.onHomeStatusChanged,
    this.onSelectedHomeChanged,
    this.onOpenDevices,
    this.onOpenServices,
  });

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  bool _loading = true;
  String? _error;
  final _homeBox = Hive.box<HomeModel>('homes');

  bool _fetchInFlight = false;

  // True while a pull-to-refresh is running in the background.
  bool _refreshing = false;

  // Each entry: { id, address, pincode, members, rooms: {roomKey: [items]}, roomIds }
  List<Map<String, dynamic>> _homes = [];
  int _selectedHomeIndex = 0;

  // Source of truth for the selected home. Index can shift when the list is
  // re-ordered, so after every refresh we re-find the home by this id.
  String? _selectedHomeId;

  // MainShell sollura "intha home ah select pannu" request (new home create aana apram).
  String? _pendingSelectHomeId;

  // Last values sent to MainShell (avoid redundant notifications).
  String? _lastNotifiedId;
  String? _lastNotifiedAddress;
  String? _lastNotifiedPincode;

  // Name entered while registering (replaces "Guest" until app restarts).
  String? _nameOverride;
  String get _displayName => _nameOverride ?? widget.name;

  // Hidden placeholder room used by AddressScreen to force home creation at
  // signup time. Never shown anywhere in the UI.
  static const String _hiddenSetupRoomKey = '__setup__';

  // Every new appliance is saved under this room name.
  static const String _defaultRoomName = 'Default';

  static const int _maxDevicesOnHome = 3;

  static const Map<String, IconData> _applianceIcons = {
    'fridge': Icons.kitchen_rounded,
    'refrigerator': Icons.kitchen_rounded,
    'stove': Icons.local_fire_department_rounded,
    'ac': Icons.ac_unit_rounded,
    'air conditioner': Icons.ac_unit_rounded,
    'washing machine': Icons.local_laundry_service_rounded,
    'tv': Icons.tv_rounded,
    'television': Icons.tv_rounded,
    'mixer': Icons.blender_rounded,
    'geyser': Icons.hot_tub_rounded,
    'water heater': Icons.hot_tub_rounded,
    'router': Icons.router_rounded,
    'fan': Icons.mode_fan_off_rounded,
    'microwave': Icons.microwave_rounded,
    'water purifier': Icons.water_drop_rounded,
  };

  // serviceType -> provider count, shown as "X nearby".
  final Map<String, int> _serviceCounts = {};

  // Counts are cached per pincode so they still show when the network is off.
  final _sessionBox = Hive.box('session');

  // True while the background "cache every appliance's providers" job runs.
  bool _prefetching = false;

    String get _countsKey =>
      'serviceCounts:${_hasRegisteredHome ? (_currentHomeId ?? _currentPincode) : 'gps'}';

  // Last known counts (offline-ku).
  void _loadCachedCounts() {
    try {
      final raw = _sessionBox.get(_countsKey);
      _serviceCounts.clear();
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is num) _serviceCounts[k.toString()] = v.toInt();
        });
      }
    } catch (e) {
      debugPrint('❌ Load cached counts error: $e');
    }
  }

  // Register aagaadha user-ku current location use pannum
  double? _lat;
  double? _lng;

  bool get _useGps => !_hasRegisteredHome && _lat != null && _lng != null;

  Future<void> _loadGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      _prefetchServiceCounts();
      _prefetchAllApplianceProviders();
    } catch (e) {
      debugPrint('❌ Home GPS error: $e');
    }
  }

  // ── Banner carousel ──
  final PageController _bannerController = PageController(viewportFraction: 0.92);
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) return;
            final count = BannerLoader.banners.value.length;
      if (count == 0) return;
      final next = (_bannerIndex + 1) % count;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    applianceAddRequest.removeListener(_onApplianceAddRequest);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ApplianceServicesLoader.load().then((_) {
  if (mounted) _prefetchAllApplianceProviders();
});
    applianceAddRequest.addListener(_onApplianceAddRequest);
    _loadCachedCounts();
    _fetchAppliances();
    _prefetchServiceCounts();
    _loadGps();
    _startBannerTimer();
        BannerLoader.load();
  }

  void _onApplianceAddRequest() {
    final name = applianceAddRequest.value;
    if (name == null) return;
    applianceAddRequest.value = null; // consume
    if (mounted) _openManualAddDialog(prefillProduct: name);
  }

  // Called by MainShell when the Home tab is tapped.
  // Service counts are NOT cleared here (avoids "..." flicker) — the old
  // numbers stay visible and get replaced when the new ones arrive.
  Future<void> refresh({String? selectHomeId}) async {
    if (selectHomeId != null) _pendingSelectHomeId = selectHomeId;
    while (_fetchInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _fetchAppliances();
    if (!mounted) return;
    _notifySelectedHome();
    _prefetchServiceCounts();
  }

  // Pull-to-refresh handler.
  Future<void> _silentRefresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      if (_currentHomeId != null) {
        await _fetchAppliances(homeId: _currentHomeId);
      } else {
        await _fetchAppliances();
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------
  // SERVICES NEAR YOU — data (shared HomeServices, pincode only)
  // ---------------------------------------------------------------------
  void _prefetchServiceCounts() {
    final key = _countsKey;
    HomeServices.prefetchCounts(
      _currentPincode,
      (type, count) {
        if (!mounted) return;
        setState(() => _serviceCounts[type] = count);
        _sessionBox.put(key, Map<String, int>.from(_serviceCounts));
      },
      latitude: _searchLat,
      longitude: _searchLng,
    );
  }

  // ---------------------------------------------------------------------
  // OFFLINE PREFETCH — every appliance's nearby providers, cached in Hive
  // so the provider sheet works offline for ANY appliance.
  // ---------------------------------------------------------------------
  Future<void> _prefetchAllApplianceProviders() async {
    if (_prefetching) return;
    if (_homes.isEmpty) return; // wait until homes are loaded

    // Location: pincode irundha pincode, illa na GPS.
           final pin = _currentPincode;
    final usePin = pin.isNotEmpty;
    final lat = _searchLat;
    final lng = _searchLng;
    if (lat == null || lng == null) return; // backend needs coordinates
    final loc =
        'h:${_currentHomeId ?? 'gps'}:${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';

    // V3 key: old stamps ignored.
    final stampKey = 'nearbyPrefetchV3:$loc';
    final last = _sessionBox.get(stampKey);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (last is int && nowMs - last < 12 * 3600 * 1000) return;

    final names = <String>{};
    for (final g in ApplianceServicesLoader.groups.value) {
      for (final it in (g['items'] as List)) {
        final n = it?.toString().trim();
        if (n != null && n.isNotEmpty) names.add(n);
      }
    }

    final list = names.toList();
    debugPrint('🔧 Prefetch start: ${list.length} appliances, loc $loc');
    if (list.isEmpty) return;

    _prefetching = true;
    try {
      var okCount = 0;
      for (int i = 0; i < list.length; i += 4) {
        if (!mounted) return;
        final results = await Future.wait(list.skip(i).take(4).map((n) {
                    return prefetchNearbyProviders(DeviceEntry(
            homeId: _currentHomeId,
            homeAddress: _currentAddress,
            pincode: usePin ? pin : '',
            roomKey: _defaultRoomName.toLowerCase(),
            roomName: _defaultRoomName,
            raw: {'product': n, 'brand': ''},
            latitude: lat,
            longitude: lng,
          ));
        }));
        okCount += results.where((r) => r).length;
        if (i == 0 && okCount == 0) {
          debugPrint('🔧 Prefetch stopped: offline');
          return;
        }
      }
      debugPrint('🔧 Prefetch done: $okCount/${list.length} cached');
      if (okCount == list.length) _sessionBox.put(stampKey, nowMs);
    } finally {
      _prefetching = false;
    }
  }

  // ---------------------------------------------------------------------
  // ICON HELPERS
  // ---------------------------------------------------------------------
  IconData _iconForAppliance(String product) {
    final key = product.toLowerCase();
    for (final entry in _applianceIcons.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return Icons.devices_other_rounded;
  }

  // ---------------------------------------------------------------------
  // FETCH
  // ---------------------------------------------------------------------
  Future<void> _fetchAppliances({String? homeId}) async {
    final isSingleHomeRefresh = homeId != null;

    // Skip if a full refresh is already running.
    if (!isSingleHomeRefresh) {
      if (_fetchInFlight) return;
      _fetchInFlight = true;
    }

    // Show cache instantly — full refresh only.
    if (!isSingleHomeRefresh) {
      if (_homeBox.isNotEmpty && mounted) {
        setState(() {
          _homes = _homeBox.values.map((h) => h.toMap()).toList();
          _restoreSelection();
          _loadCachedCounts();
          _loading = false;
        });
      } else if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    }

    try {
      final plainMobile = ApiConfig.stripCountryCode(widget.mobileNumber);
      final url = ApiConfig.submissionSearchWith(plainMobile, homeId: isSingleHomeRefresh ? homeId : null);

      final response = await ApiClient.get(url);
      debugPrint('🏠 Home fetch status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List rawHomes = rawData is List ? rawData : [rawData];

          final parsedHomes = rawHomes.map<Map<String, dynamic>>((h) {
            final roomsRaw = h['rooms'];
            final Map<String, List<Map<String, dynamic>>> rooms = {};
            final Map<String, String> roomIds = {}; // roomKey -> backend room _id

            if (roomsRaw is List) {
              for (final roomObj in roomsRaw) {
                if (roomObj is! Map) continue;
                final roomName = roomObj['roomName']?.toString();
                final devicesRaw = roomObj['devices'];
                if (roomName == null || devicesRaw is! List) continue;
                if (roomName.toLowerCase() == _hiddenSetupRoomKey) continue;

                final key = roomName.toLowerCase();

                // append, don't overwrite
                rooms.putIfAbsent(key, () => []).addAll(
                      devicesRaw.map((e) => Map<String, dynamic>.from(e as Map)),
                    );

                final rid = (roomObj['_id'] ?? roomObj['roomId'])?.toString();
                if (rid != null && rid.isNotEmpty) roomIds[key] = rid;
              }
            } else if (roomsRaw is Map) {
              roomsRaw.forEach((key, value) {
                if (value is List) {
                  if (key.toString().toLowerCase() == _hiddenSetupRoomKey) return;
                  rooms.putIfAbsent(key.toString().toLowerCase(), () => []).addAll(
                        value.map((e) => Map<String, dynamic>.from(e as Map)),
                      );
                }
              });
            }

            final membersRaw = h['members'];
            final List<Map<String, dynamic>> members = membersRaw is List
                ? membersRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : <Map<String, dynamic>>[];

            return {
              'id': (h['_id'] ?? h['id'])?.toString(),
              'address': h['address']?.toString() ?? widget.address,
              'pincode': h['pincode']?.toString() ?? widget.pincode,
                            'homeName': h['homeName']?.toString(),
                                          'latitude': h['latitude'],
              'longitude': h['longitude'],
              'rooms': rooms,
              'roomIds': roomIds,
              'members': members,
            };
          }).toList();

          final dedupedHomes = _dedupeHomes(parsedHomes);

          // ---------- Single home refresh: ONLY that home is touched ----------
          if (isSingleHomeRefresh) {
            final matches = dedupedHomes.where((h) => h['id']?.toString() == homeId).toList();
            if (matches.isEmpty || !mounted) return;

            final updated = matches.first;
            final idx = _homes.indexWhere((h) => h['id']?.toString() == homeId);
            setState(() {
              if (idx != -1) {
                _homes[idx] = updated;
              } else {
                _homes.add(updated);
              }
              _restoreSelection();
            });
            await _homeBox.clear();
            for (final h in _homes) {
              await _homeBox.add(HomeModel.fromMap(h));
            }
            return;
          }

          // ---------- Full refresh ----------
          final ordered = _stableOrderHomes(_homes, dedupedHomes);
          await _homeBox.clear();
          for (final h in ordered) {
            await _homeBox.add(HomeModel.fromMap(h));
          }

          if (mounted) {
            setState(() {
              _homes = ordered;
              _restoreSelection();
              _loading = false;
            });
                        // Homes are loaded -> coordinates known -> counts + provider cache.
            _prefetchServiceCounts();
            _prefetchAllApplianceProviders();
          }
          return;
        }
      }

      if (isSingleHomeRefresh) return;

      if (mounted && _homeBox.isEmpty) {
        setState(() {
          _homes = [];
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('❌ Home fetch error (network): $e');
      if (isSingleHomeRefresh) return;
      if (mounted) {
        setState(() {
          if (_homeBox.isEmpty) {
            _error = AppStrings.homeLoadError;
          }
          _loading = false;
        });
      }
    } finally {
      if (!isSingleHomeRefresh) _fetchInFlight = false;
    }
  }

  // Same address+pincode (or same id) collapse into ONE home.
  List<Map<String, dynamic>> _dedupeHomes(List<Map<String, dynamic>> homes) {
    final Map<String, Map<String, dynamic>> merged = {};
    final List<String> order = [];
    for (final home in homes) {
      final id = home['id']?.toString();
      final address = home['address']?.toString() ?? '';
      final pincode = home['pincode']?.toString() ?? '';
      final key = (id != null && id.isNotEmpty)
          ? 'id:$id'
          : 'addr:${address.trim().toLowerCase()}|${pincode.trim()}';
      if (!merged.containsKey(key)) {
        final roomsIn = home['rooms'] as Map<String, List<Map<String, dynamic>>>;
        final roomIdsIn = (home['roomIds'] as Map<String, String>?) ?? {};
        merged[key] = {
          'id': home['id'],
          'address': home['address'],
          'pincode': home['pincode'],
           'homeName': home['homeName'],
                     'latitude': home['latitude'],
          'longitude': home['longitude'],
          'rooms': roomsIn.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v))),
          'roomIds': Map<String, String>.from(roomIdsIn),
          'members': List<Map<String, dynamic>>.from(home['members'] as List),
        };
        order.add(key);
      } else {
        final existing = merged[key]!;
        final existingRooms = existing['rooms'] as Map<String, List<Map<String, dynamic>>>;
        final incomingRooms = home['rooms'] as Map<String, List<Map<String, dynamic>>>;
        incomingRooms.forEach((roomKey, items) {
          if (existingRooms.containsKey(roomKey)) {
            existingRooms[roomKey] = [...existingRooms[roomKey]!, ...items];
          } else {
            existingRooms[roomKey] = List<Map<String, dynamic>>.from(items);
          }
        });
        final existingRoomIds = existing['roomIds'] as Map<String, String>;
        existingRoomIds.addAll((home['roomIds'] as Map<String, String>?) ?? {});
        final existingMembers = existing['members'] as List<Map<String, dynamic>>;
        final existingMobiles = existingMembers.map((m) => m['mobile']?.toString()).toSet();
        for (final m in home['members'] as List<Map<String, dynamic>>) {
          if (!existingMobiles.contains(m['mobile']?.toString())) existingMembers.add(m);
        }
      }
    }
    return order.map((key) => merged[key]!).toList();
  }

  // Keep tab order stable across refreshes.
  List<Map<String, dynamic>> _stableOrderHomes(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> incoming,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final h in incoming)
        if (h['id'] != null && h['id'].toString().isNotEmpty) h['id'].toString(): h,
    };
    final ordered = <Map<String, dynamic>>[];
    final used = <String>{};
    for (final old in previous) {
      final id = old['id']?.toString();
      if (id != null && byId.containsKey(id)) {
        ordered.add(byId[id]!);
        used.add(id);
      }
    }
    for (final h in incoming) {
      final id = h['id']?.toString();
      if (id == null || !used.contains(id)) ordered.add(h);
    }
    return ordered;
  }

  // ---------------------------------------------------------------------
  // CURRENT HOME HELPERS
  // ---------------------------------------------------------------------
  Map<String, dynamic>? get _currentHome =>
      (_homes.isEmpty || _selectedHomeIndex >= _homes.length) ? null : _homes[_selectedHomeIndex];

  // After any list change, point the index back at the SAME home (by id).
  void _restoreSelection() {
    if (_homes.isEmpty) {
      _selectedHomeIndex = 0;
      return;
    }

    // Pudhusa create aana home ah select pannanum na, adhu list la vandha udane pick pannu.
    if (_pendingSelectHomeId != null) {
      final p = _homes.indexWhere((h) => h['id']?.toString() == _pendingSelectHomeId);
      if (p != -1) {
        _selectedHomeIndex = p;
        _selectedHomeId = _pendingSelectHomeId;
        _pendingSelectHomeId = null;
        return;
      }
    }

    if (_selectedHomeId != null) {
      final i = _homes.indexWhere((h) => h['id']?.toString() == _selectedHomeId);
      if (i != -1) {
        _selectedHomeIndex = i;
        return;
      }
    }
    if (_selectedHomeIndex >= _homes.length) _selectedHomeIndex = 0;
    _selectedHomeId = _homes[_selectedHomeIndex]['id']?.toString();
  }

  Map<String, List<Map<String, dynamic>>> get _currentRooms =>
      (_currentHome?['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};

  // ALL devices of the current home, flattened (rooms are not shown anymore).
  List<Map<String, dynamic>> get _allDevices =>
      _currentRooms.values.expand((items) => items).toList();

  // Same devices wrapped as DeviceEntry (needed by the common details sheet).
  List<DeviceEntry> get _allDeviceEntries {
    final out = <DeviceEntry>[];
    _currentRooms.forEach((roomKey, items) {
      for (final item in items) {
        out.add(DeviceEntry(
          homeId: _currentHomeId,
          homeAddress: _currentAddress,
          pincode: _currentPincode,
          roomKey: roomKey,
          roomName: roomKey.isNotEmpty
              ? '${roomKey[0].toUpperCase()}${roomKey.substring(1)}'
              : roomKey,
          raw: item,
                    latitude: _searchLat,
          longitude: _searchLng,
        ));
      }
    });
    return out;
  }

  String? get _currentHomeId => _currentHome?['id']?.toString();
  String get _currentAddress => _currentHome?['address']?.toString() ?? widget.address;

  // Empty-string pincode on the home falls back to the widget pincode.
  String get _currentPincode {
    final p = _currentHome?['pincode']?.toString().trim() ?? '';
    return p.isNotEmpty ? p : widget.pincode;
  }
    double? get _currentHomeLat =>
      double.tryParse(_currentHome?['latitude']?.toString() ?? '');
  double? get _currentHomeLng =>
      double.tryParse(_currentHome?['longitude']?.toString() ?? '');
        // Registered home -> home oda saved lat/lng (illana GPS). Register aagala -> GPS.
  double? get _searchLat =>
      _hasRegisteredHome ? (_currentHomeLat ?? _lat) : _lat;
  double? get _searchLng =>
      _hasRegisteredHome ? (_currentHomeLng ?? _lng) : _lng;

  void _notifySelectedHome() {
    final id = _currentHomeId;
    final addr = _currentAddress;
    final pin = _currentPincode;
    if (id == _lastNotifiedId && addr == _lastNotifiedAddress && pin == _lastNotifiedPincode) {
      return;
    }
    _lastNotifiedId = id;
    _lastNotifiedAddress = addr;
    _lastNotifiedPincode = pin;
    widget.onSelectedHomeChanged?.call(id, addr, pin);
  }

    String _homeLabel(Map<String, dynamic> home, int index) {
    final saved = home['homeName']?.toString().trim() ?? '';
    if (saved.isNotEmpty && saved.toLowerCase() != 'default home') return saved;
    final address = home['address']?.toString() ?? '';
    final firstPart = address.split(',').first.trim();
    return firstPart.isNotEmpty ? firstPart : AppStrings.homeN(index + 1);
  }

  bool _isDefaultHome(Map<String, dynamic> home) {
    final addr = home['address']?.toString().trim().toLowerCase() ?? '';
    return addr == 'default';
  }

  bool get _hasRegisteredHome => _homes.any((h) => !_isDefaultHome(h));

  Map<String, dynamic>? get _defaultHome {
    for (final h in _homes) {
      if (_isDefaultHome(h)) return h;
    }
    return null;
  }

  void _requestScan() {
    widget.onScanTap?.call(
      homeId: _currentHomeId,
      address: _currentAddress,
      pincode: _currentPincode,
    );
  }

  void _openDevicesTabWith(String filter) {
    devicesFilterRequest.value = filter;
    widget.onOpenDevices?.call(filter);
  }

  // Card tap -> common details sheet (same as Devices tab).
  void _openDeviceDetails(DeviceEntry e) {
    showDeviceDetailsSheet(
      context,
      e,
      mobileNumber: widget.mobileNumber,
      name: _displayName,
      onChanged: () {
        if (_currentHomeId != null) {
          _fetchAppliances(homeId: _currentHomeId);
        } else {
          _fetchAppliances();
        }
      },
    );
  }

  // ---------------------------------------------------------------------
  // WARRANTY HELPERS
  // ---------------------------------------------------------------------
  DateTime? _expiryOf(Map<String, dynamic> item) {
    return WarrantyUtils.parseExpiry(
      item['warranty']?.toString(),
      referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
    );
  }

  // ---------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------
  Map<String, int> _computeStats() {
    int active = 0;
    int attention = 0;
    final now = DateTime.now();
    final devices = _allDevices;

    for (final item in devices) {
      final expiry = _expiryOf(item);
      if (expiry == null) continue;
      if (expiry.isAfter(now)) {
        active++;
        if (expiry.difference(now).inDays <= 30) attention++; // expiring soon
      } else {
        attention++; // expired
      }
    }

    return {'devices': devices.length, 'active': active, 'attention': attention};
  }

  // ---------------------------------------------------------------------
  // DEVICES SCREEN (re-uses the old room detail screen, shows ALL devices)
  // ---------------------------------------------------------------------
  void _openDevicesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(
          roomKey: _defaultRoomName.toLowerCase(),
          roomName: AppStrings.allDevices,
          items: _allDevices,
          iconForAppliance: _iconForAppliance,
          mobileNumber: widget.mobileNumber,
          address: _currentAddress,
          pincode: _currentPincode,
          name: _displayName,
          homeId: _currentHomeId,
        ),
      ),
    ).then((_) {
      if (_currentHomeId != null) {
        _fetchAppliances(homeId: _currentHomeId);
      } else {
        _fetchAppliances();
      }
    });
  }

  // Devices that live in the "Default" home (skip-flow).
  void _openDefaultHomeDevices() {
    final dh = _defaultHome;
    if (dh == null) return;
    final rooms = (dh['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};
    final items = rooms.values.expand((l) => l).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(
          roomKey: _defaultRoomName.toLowerCase(),
          roomName: AppStrings.allDevices,
          items: items,
          iconForAppliance: _iconForAppliance,
          mobileNumber: widget.mobileNumber,
          address: dh['address']?.toString() ?? widget.address,
          pincode: dh['pincode']?.toString() ?? widget.pincode,
          name: _displayName,
          homeId: dh['id']?.toString(),
        ),
      ),
    ).then((_) => _fetchAppliances());
  }

  // ---------------------------------------------------------------------
  // ADD HOME — pushes AddressScreen (isAddingHome: true).
  //  REGISTER flow : user has only the Guest/"Default" home -> UPDATE it.
  //  ADD-HOME flow : user already has a registered home -> CREATE a new one.
  // ---------------------------------------------------------------------
 void _openAddHomeDialog() async {
    final bool isRegisterFlow = !_hasRegisteredHome;

    String? existingDefaultId;
    if (isRegisterFlow) {
      existingDefaultId = _defaultHome?['id']?.toString();
    }

    debugPrint('🏠 isRegisterFlow=$isRegisterFlow existingDefaultId=$existingDefaultId');

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressScreen(
          mobileNumber: widget.mobileNumber,
          isAddingHome: true,
        ),
      ),
    );

    if (result == null || !mounted) return;

        final newAddress = result['address']?.toString() ?? '';
    final newPincode = result['pincode']?.toString() ?? '';
    if (newAddress.isEmpty) return;
    final newName = (result['name'] ?? '').toString().trim();
    final enteredHomeName = (result['homeName'] ?? '').toString().trim();
    final pinLat = (result['latitude'] as num?)?.toDouble();
    final pinLng = (result['longitude'] as num?)?.toDouble();
    final firstPart = newAddress.split(',').first.trim();
    if (newName.isNotEmpty) setState(() => _nameOverride = newName);

    // ---------- UPDATE the Default (Guest) home ----------
    if (existingDefaultId != null) {
      debugPrint('✏️ Updating Default home $existingDefaultId -> $newAddress');
            final ok = await _submitAddressUpdate(
        existingDefaultId,
        newAddress,
        newPincode,
        homeName: enteredHomeName.isNotEmpty
            ? enteredHomeName
            : (firstPart.isNotEmpty ? firstPart : 'Home'),
        name: newName.isNotEmpty ? newName : null,
        latitude: pinLat,
        longitude: pinLng,
      );
      if (ok && mounted) {
        if (newName.isNotEmpty) {
          setState(() => _nameOverride = newName);
          widget.onNameChanged?.call(newName);
          await SessionManager.saveSession(
            mobileNumber: widget.mobileNumber,
            address: newAddress,
            pincode: newPincode,
            name: newName,
            homeId: existingDefaultId,
          );
        }
        await _fetchAppliances(homeId: existingDefaultId);
        if (!mounted) return;
        setState(() {
          final idx = _homes.indexWhere((h) => h['id']?.toString() == existingDefaultId);
          if (idx != -1) {
            _selectedHomeIndex = idx;
            _selectedHomeId = existingDefaultId;
          }
          _loadCachedCounts();
        });
        await SessionManager.updateHomeId(existingDefaultId);
        _notifySelectedHome();
        _prefetchServiceCounts();
        _prefetchAllApplianceProviders();
      }
      return;
    }

    // ---------- CREATE a brand-new home ----------
    debugPrint('🆕 Creating NEW home -> $newAddress');
        final newHomeId = await _createNewHomeRecord(
      address: newAddress,
      pincode: newPincode,
      name: newName.isNotEmpty ? newName : _displayName,
      homeName: enteredHomeName.isNotEmpty
          ? enteredHomeName
          : (firstPart.isNotEmpty ? firstPart : AppStrings.homeN(_homes.length + 1)),
      latitude: pinLat,
      longitude: pinLng,
    );

    if (newHomeId == null) {
      _snack(AppStrings.couldNotCreateHome);
      return;
    }

    while (_fetchInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _fetchAppliances();
    if (!mounted) return;
    setState(() {
      final idx = _homes.indexWhere((h) => h['id']?.toString() == newHomeId);
      _selectedHomeIndex = idx != -1 ? idx : (_homes.isEmpty ? 0 : _homes.length - 1);
      _selectedHomeId = _homes.isNotEmpty ? _homes[_selectedHomeIndex]['id']?.toString() : null;
      _loadCachedCounts();
    });
    await SessionManager.updateHomeId(newHomeId);
    _notifySelectedHome();
    _prefetchServiceCounts();
    _prefetchAllApplianceProviders();
    _snack(AppStrings.homeAdded);
  }

  // ── Edit the currently selected home (name / address / pincode) ──
  void _openEditHomeDialog() {
    final home = _currentHome;
    final homeId = home?['id']?.toString();
    if (home == null || homeId == null) return;

    final savedName = home['homeName']?.toString().trim() ?? '';
    final nameController = TextEditingController(
        text: savedName.toLowerCase() == 'default home' ? '' : savedName);
    final addressController =
        TextEditingController(text: home['address']?.toString() ?? '');
    final pincodeController =
        TextEditingController(text: home['pincode']?.toString() ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: AppDecor.dialogShape,
          title: const Text('Edit home', style: AppText.dialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppDialogField(controller: nameController, hint: 'Home name'),
                const SizedBox(height: 12),
                AppDialogField(controller: addressController, hint: 'Address'),
                const SizedBox(height: 12),
                AppDialogField(
                    controller: pincodeController,
                    hint: 'Pincode',
                    keyboardType: TextInputType.number,
                    maxLength: 6),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: isSaving
                  ? null
                  : () async {
                      final newAddress = addressController.text.trim();
                      final newPincode = pincodeController.text.trim();
                      final newName = nameController.text.trim();
                      if (newAddress.isEmpty) {
                        _snack('Please enter the address');
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      final ok = await _submitAddressUpdate(
                        homeId,
                        newAddress,
                        newPincode,
                        homeName: newName.isNotEmpty ? newName : null,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (ok && mounted) {
                        await _fetchAppliances(homeId: homeId);
                        if (!mounted) return;
                        setState(_loadCachedCounts);
                        _notifySelectedHome();
                        _prefetchServiceCounts();
                        _prefetchAllApplianceProviders();
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.onPrimary, strokeWidth: 2))
                  : Text(AppStrings.save, style: TextStyle(color: AppColors.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // Creates a brand-new home on the backend and returns its homeId.
    Future<String?> _createNewHomeRecord({
    required String address,
    required String pincode,
    required String name,
    required String homeName,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final deviceId = await DeviceIdService.getDeviceId();
      final fcmToken = await ApiClient.safeFcmToken();

      if (authToken == null) {
        debugPrint('❌ No Firebase auth token — user not signed in?');
        _snack(AppStrings.signInAgainToAddHome);
        return null;
      }

      final response = await http.post(
        Uri.parse(ApiConfig.createHomeUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'x-auth-token': authToken,
          'x-device-id': deviceId,
        },
        body: jsonEncode({
          'name': name,
          'mobile': ApiConfig.stripCountryCode(widget.mobileNumber),
          'address': address,
          'pincode': pincode,
          'homeName': homeName,
                    if (latitude != null && longitude != null) ...{
            'latitude': latitude,
            'longitude': longitude,
          },
          'PlatformInfo': {
            'device': {
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'os': Platform.isAndroid ? 'android' : 'ios',
            },
          },
        }),
      );

      debugPrint('🏠 Create home status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final homeId = data['data']['homeId']?.toString();
          if (homeId != null && homeId.isNotEmpty) {
            await SessionManager.updateHomeId(homeId);
          }
          return homeId;
        }
      }
    } catch (e) {
      debugPrint('❌ Create home error: $e');
    }
    return null;
  }

      Future<bool> _submitAddressUpdate(
    String homeId,
    String address,
    String pincode, {
    String? homeName,
    String? name,
    double? latitude,
    double? longitude,
  }) async {
    final result = await EntityUpdateService.update(
      homeId: homeId,
      address: address,
      pincode: pincode.isNotEmpty ? pincode : null,
      homeName: homeName,
      name: name,
      latitude: latitude,
      longitude: longitude,
    );

    if (!mounted) return false;

    _snack(result['success'] == true
        ? AppStrings.addressUpdated
        : (result['message']?.toString() ?? AppStrings.addressUpdateFailed));
    return result['success'] == true;
  }

  // ---------------------------------------------------------------------
  // MANUAL ADD — product / brand / warranty. No room: always "Default".
  // ---------------------------------------------------------------------
  void _openManualAddDialog({String? prefillProduct}) {
    final productController = TextEditingController(text: prefillProduct ?? '');
    final brandController = TextEditingController();
    final warrantyController = TextEditingController();
    bool isSubmitting = false;

    StateSetter? refreshDialog;
    productController.addListener(() => refreshDialog?.call(() {}));

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            refreshDialog = setDialogState;
            final productHasText = productController.text.trim().isNotEmpty;
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: AppDecor.dialogShape,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(AppStrings.addApplianceTitle, style: AppText.dialogTitle),
                  InkWell(
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _requestScan();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 4),
                          const Text(AppStrings.scan, style: AppText.linkAction),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDialogField(
                      controller: productController,
                      hint: AppStrings.productNameHintExample,
                    ),
                    const SizedBox(height: 10),
                    AppDialogField(controller: brandController, hint: AppStrings.brandOptionalHint),
                    const SizedBox(height: 10),
                    AppDialogField(
                        controller: warrantyController, hint: AppStrings.warrantyOptionalHint),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel, style: AppText.cancelAction),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: (isSubmitting || !productHasText)
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final ok = await _submitManualAppliance(
                            product: productController.text.trim(),
                            brand: brandController.text.trim(),
                            warranty: warrantyController.text.trim(),
                          );
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (ok) {
                            if (_currentHomeId != null) {
                              _fetchAppliances(homeId: _currentHomeId);
                            } else {
                              _fetchAppliances();
                            }
                          }
                        },
                  child: isSubmitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2),
                        )
                      : Text(AppStrings.addApplianceButton, style: TextStyle(color: AppColors.onPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitManualAppliance({
    required String product,
    required String brand,
    required String warranty,
  }) async {
    try {
      String? homeIdToUse = _currentHomeId;
      if (homeIdToUse == null) {
        final response = await ApiClient.post(ApiConfig.createHomeUrl, body: {
          'name': _displayName,
          'mobile': ApiConfig.stripCountryCode(widget.mobileNumber),
          'address': _currentAddress,
          'homeName': _currentAddress.split(',').first.trim(),
        });
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            homeIdToUse = data['data']['homeId']?.toString();
          }
        }
        if (homeIdToUse == null) {
          _snack(AppStrings.couldNotSetupHome);
          return false;
        }
        await SessionManager.updateHomeId(homeIdToUse);
      }

      final request = http.MultipartRequest('POST', Uri.parse(ApiConfig.productSubmitUrl));
      request.headers.addAll(await ApiClient.authHeaders());

      request.fields['homeId'] = homeIdToUse;
      request.fields['address'] = _currentAddress;
      request.fields['product'] = product;
      request.fields['brand'] = brand.isNotEmpty ? brand : 'Unknown';
      request.fields['mobile'] = ApiConfig.stripCountryCode(widget.mobileNumber);
      request.fields['pincode'] = _currentPincode;
      request.fields['warranty'] = warranty.isNotEmpty ? warranty : 'N/A';
      request.fields['roomName'] = _defaultRoomName;
      request.fields['name'] = _displayName;

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      debugPrint('📦 Manual submit status: ${response.statusCode}');

      if (!mounted) return false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _snack(AppStrings.applianceAdded(product));
        return true;
      }
      final data = jsonDecode(response.body);
      _snack(data['message']?.toString() ?? AppStrings.couldNotAddAppliance);
      return false;
    } catch (e) {
      debugPrint('❌ Manual submit error: $e');
      _snack(AppStrings.networkError);
      return false;
    }
  }

  // =====================================================================
  // BUILD
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    final hasHome = !_loading && _hasRegisteredHome;

    if (!_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onHomeStatusChanged?.call(hasHome);
        _notifySelectedHome();
      });
    }

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.notifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.lightBg,
          body: SafeArea(
            top: false,
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppColors.lightPrimary))
                : Stack(
                    children: [
                      // No stretch / bounce: content never moves while pulling.
                      ScrollConfiguration(
                        behavior: const _NoStretchScrollBehavior(),
                        child: RefreshIndicator(
                          color: AppColors.lightPrimary,
                          edgeOffset: MediaQuery.of(context).padding.top,
                          onRefresh: _silentRefresh,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: ClampingScrollPhysics()),
                            slivers: [
                              SliverToBoxAdapter(child: _buildHeader()),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate([
                                    if (_error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Text(_error!,
                                            style: TextStyle(color: AppColors.danger)),
                                      )
                                    else if (!hasHome) ...[
                                      _buildRegisterHomeCard(),
                                      _buildDefaultHomePreview(),
                                      const SizedBox(height: 24),
                                      _buildAppliancesGadgets(),
                                      const SizedBox(height: 24),
                                      _buildServicesNearYou(),
                                    ] else ...[
                                      // Devices are INSIDE the active home card.
                                      _buildActiveHomeCard(),
                                      const SizedBox(height: 24),
                                      _buildAppliancesGadgets(),
                                      const SizedBox(height: 24),
                                      _buildServicesNearYou(),
                                    ],
                                  ]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

Widget _buildHeader() {
  final hasName = _displayName.isNotEmpty && _displayName.toLowerCase() != 'guest';
  final current = _currentHome;
  final registeredCount = _homes.where((h) => !_isDefaultHome(h)).length;
  final title = current == null ? AppStrings.select : _homeLabel(current, _selectedHomeIndex);
 final address = current?['address']?.toString().trim() ?? ''; 
  final parts = address.split(',');                                                        // 👈 add
  final shortAddress = parts.length > 1 ? parts.skip(1).join(',').trim() : address;   
  final topPad = MediaQuery.of(context).padding.top;

  return Container(
  width: double.infinity,
  color: AppColors.lightBg, // page background maari plain
  child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top bar: logo | home switcher | profile ──
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            boxShadow: const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    _buildBrandLogo(),
              const SizedBox(width: 8),
              Expanded(
                child: (_hasRegisteredHome && current != null)
                    ? _buildHomeSwitcher(
                        registeredCount,
                        trigger: Row(
                          children: [
                            Container(
  width: 32,
  height: 32,
  decoration: BoxDecoration(
    color: AppColors.lightPrimary.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Icon(Icons.home_outlined,
      size: 16, color: AppColors.lightPrimary),
),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppType.headerTitle.copyWith(color: AppColors.lightTextDark)),
                                      ),
                                      Icon(Icons.keyboard_arrow_down_rounded,
                                          size: 20, color: AppColors.lightTextMuted),
                                    ],
                                  ),
                                  Text(shortAddress,                      // 👈 inga
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.lightCaption),
    ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
             GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: widget.onProfileTap,
  child: SizedBox(
    width: 40,
    height: 40,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.only(top: 2, right: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lightPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: AppColors.lightPrimary.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Text(
              hasName ? _displayName[0].toUpperCase() : 'P',
              style: TextStyle(
                color: AppColors.lightPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
        // green online dot (top-right)
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBg, width: 2),
            ),
          ),
        ),
      ],
    ),
  ),
),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Banner carousel (unchanged) ──
        ValueListenableBuilder<List<String>>(
          valueListenable: BannerLoader.banners,
          builder: (context, images, _) {
            if (_bannerIndex >= images.length) _bannerIndex = 0;
            return Column(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 1.05,
                  child: PageView.builder(
                    controller: _bannerController,
                    itemCount: images.length,
                    onPageChanged: (i) {
                      setState(() => _bannerIndex = i);
                      _startBannerTimer();
                    },
                    itemBuilder: (context, i) {
                      final src = images[i];
                      final placeholder = Container(color: AppColors.lightSurface);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: src.startsWith('http')
                              ? Image.network(src,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, p) => p == null ? child : placeholder,
                                  errorBuilder: (_, __, ___) => placeholder)
                              : Image.asset(src,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => placeholder),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < images.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _bannerIndex ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _bannerIndex
                              ? AppColors.lightPrimary
                              : AppColors.textPrimary.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

// Theme-aware brand logo (replaces the "ZHINI" text)
// Same logo as the login screen
Widget _buildBrandLogo() {
  return const ZhiniLogo(size: 40);
}

  // ── ACTIVE HOME card: home name, members avatars, devices, Switch dropdown ──
  Widget _buildActiveHomeCard() {
    final current = _currentHome;
    final deviceCount = _allDevices.length;
    final myPlain = ApiConfig.stripCountryCode(widget.mobileNumber);
    final members = (current?['members'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];

    const avatarColors = [
      Color(0xFF2563EB),
      Color(0xFF7C6FE8),
      Color(0xFF38A3D8),
      Color(0xFF16A34A),
      Color(0xFFD97706),
    ];
    const double size = 24;
    const double overlap = 16;

    String initialOf(Map<String, dynamic> m) {
      if (m['mobile']?.toString() == myPlain) return 'Y';
      final n = (m['name']?.toString() ?? '').trim();
      return n.isEmpty ? 'M' : n[0].toUpperCase();
    }

    // Max 4 avatars, anything more is shown as "+N".
// Max 3 avatars, anything more is shown as "+N".
Widget avatars() {
  const maxShown = 2;
  final extra = members.length - maxShown;
  final shown = members.take(maxShown).toList();
  final slots = shown.length + (extra > 0 ? 1 : 0);

      Widget bubble({required Color color, required Widget child, required int index}) {
        return Positioned(
          left: index * overlap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBg, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ),
        );
      }

      return SizedBox(
        height: size,
        width: slots == 0 ? 0 : overlap * (slots - 1) + size,
        child: Stack(
          children: [
            for (int i = 0; i < shown.length; i++)
              bubble(
                index: i,
                color: avatarColors[i % avatarColors.length],
                child: Text(
                  initialOf(shown[i]),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            if (extra > 0)
              bubble(
                index: shown.length,
                color: AppColors.lightTextMuted,
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.lightCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Members (avatars next to the count) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
  children: [
    Text('Members',
        style: AppType.headerTitle.copyWith(color: AppColors.lightTextDark)),
    if (members.isNotEmpty) ...[
      const SizedBox(width: 8),
      Flexible(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: avatars(),
          ),
        ),
      ),
    ],
  ],
),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.onProfileTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Manage', style: AppText.lightLink),
              ),
            ],
          ),

          // ── Devices (same layer, inside the Active Home card) ──
          Divider(height: 24, color: AppColors.lightBorder),
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Devices ',
                      style: AppType.headerTitle.copyWith(color: AppColors.lightTextDark)),
                  TextSpan(
                      text: '($deviceCount)',
                      style: AppType.body.copyWith(color: AppColors.lightTextMuted)),
                ])),
              ),
              if (deviceCount > _maxDevicesOnHome)
                TextButton(
                  onPressed: () => _openDevicesTabWith('All'),
                  child: Text('See All', style: AppText.lightLink),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDevicesList(),
        ],
      ),
    );
  }

  // "Switch (3) ▾" dropdown
  Widget _buildHomeSwitcher(int count, {Widget? trigger}) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 40),
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        if (value == -2) {
          _openEditHomeDialog();
          return;
        }
        if (value == -1) {
          _openAddHomeDialog();
          return;
        }
        if (value == _selectedHomeIndex) return;
        setState(() {
          _selectedHomeIndex = value;
          _selectedHomeId = _homes[value]['id']?.toString();
          _loadCachedCounts();
        });
        _notifySelectedHome();
        _prefetchServiceCounts();
        _prefetchAllApplianceProviders();
      },
      itemBuilder: (context) => [
        for (int i = 0; i < _homes.length; i++)
          if (!_isDefaultHome(_homes[i]))
            PopupMenuItem<int>(
              value: i,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Row(
                  children: [
                    Icon(
                      i == _selectedHomeIndex
                          ? Icons.check_circle_rounded
                          : Icons.apartment_rounded,
                      size: 18,
                      color: i == _selectedHomeIndex
                          ? AppColors.lightPrimary
                          : AppColors.lightTextMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_homeLabel(_homes[i], i),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.lightCardTitle),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: -2,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: AppColors.lightPrimary),
              const SizedBox(width: 10),
              const Text('Edit home', style: AppText.lightLink),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: -1,
          child: Row(
            children: [
              Icon(Icons.add_circle_outline_rounded, size: 18, color: AppColors.lightPrimary),
              const SizedBox(width: 10),
              const Text(AppStrings.addNewBuilding, style: AppText.lightLink),
            ],
          ),
        ),
      ],
                   child: trigger ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count > 1 ? 'Switch ($count)' : 'Switch',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      color: AppColors.lightPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: AppColors.lightPrimary),
            ],
          ),
    );
  }

  // ── Devices list (each device = its own card) ──
  Widget _buildDevicesList() {
    final devices = _allDeviceEntries;

    if (devices.isEmpty) return const SizedBox.shrink();

    final shown = devices.take(_maxDevicesOnHome).toList();
    final isDark = ThemeController.isDark;

    return Column(
      children: [
        for (int i = 0; i < shown.length; i++)
          Container(
            margin: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardBgAlt : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
            ),
            child: _deviceRow(shown[i]),
          ),
      ],
    );
  }

  Widget _deviceRow(DeviceEntry e) {
    final product = e.raw['product']?.toString() ?? AppStrings.appliance;
    final brand = e.brand;
    final hasBrand =
        brand.isNotEmpty && brand.toLowerCase() != 'unknown' && brand.toUpperCase() != 'N/A';
    final imageUrl = e.imageUrl;
    final fallback = Icon(_iconForAppliance(product), size: 22, color: AppColors.lightPrimary);

    return InkWell(
      onTap: () => _openDeviceDetails(e),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: AppDecor.lightIconBox(radius: 12),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
                  : fallback,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.lightCardTitle),
                  const SizedBox(height: 4),
                  Text(hasBrand ? brand : AppStrings.brandNotAdded,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.lightCaption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DeviceWarrantyIndicator(e),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.lightChevron, size: 24),
          ],
        ),
      ),
    );
  }

  // ── Appliance & Gadget Services (first cards; See All -> Devices tab) ──
Widget _buildAppliancesGadgets() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Appliance & Gadget Services', style: AppText.lightSectionTitle),
                const SizedBox(height: 4),
                Text('Doorstep diagnosis & expert repair', style: AppText.lightCaption),
              ],
            ),
          ),
          TextButton(
            onPressed: () => widget.onOpenServices?.call(),
            child: Text('See All', style: AppText.lightLink),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: ApplianceServicesLoader.groups,
        builder: (context, all, _) {
          if (all.isEmpty) return const SizedBox.shrink();
          final shown = all
              .where((g) => g['show_on_home'] != false)
              .take(ApplianceServicesLoader.homeGroupCount)
              .toList();
          return ServiceGroupGrid(
            groups: shown,
            light: !ThemeController.isDark,
            compact: true,
            onTap: _openServiceGroup,
          );
        },
      ),
    ],
  );
}

  // Tap on a card -> list of ALL services in that group
  void _openServiceGroup(Map<String, dynamic> g) {
    showServiceGroupSheet(
      context,
      group: g,
      onSelect: _openApplianceService,
      onScan: _requestScan,
    );
  }

  // Tap on an appliance -> directly show nearby service providers.
   void _openApplianceService(String name) {
    final entry = DeviceEntry(
      homeId: _currentHomeId,
      homeAddress: _currentAddress,
      pincode: _currentPincode,
      roomKey: _defaultRoomName.toLowerCase(),
      roomName: _defaultRoomName,
      raw: {'product': name, 'brand': ''},
            latitude: _searchLat,
      longitude: _searchLng,
    );
    showDeviceServiceSheet(
      context,
      entry,
      mobileNumber: widget.mobileNumber,
      name: _displayName,
    );
  }

  // ── Services near you ──
  Widget _buildServicesNearYou() {
    final categories = HomeServices.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(AppStrings.servicesNearYou),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            const visible = 3.5; // 3 full cards + half of the 4th (scroll hint)
            final cardWidth = (constraints.maxWidth - gap * 3) / visible;

            return SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: gap),
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  final color = cat['color'] as Color;
                  final count = _serviceCounts[cat['type'] as String];
                  return LightCard(
                    width: cardWidth,
                    onTap: () => HomeServices.openSheet(
                      context,
                      cat,
                      _currentPincode,
                      latitude: _searchLat,
                      longitude: _searchLng,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(cat['icon'] as IconData, color: color, size: 24),
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            cat['label'] as String,
                            maxLines: 1,
                            softWrap: false,
                            style: AppText.lightCardTitle,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            count == null ? '...' : AppStrings.nearbyCount(count),
                            maxLines: 1,
                            softWrap: false,
                            style: AppText.lightSuccessCaption,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  // ── "Set Up Your Home" pill button (follows app theme) ──
  Widget _buildSetUpHomeButton() {
    final isDark = ThemeController.isDark;
    final Color fill = isDark ? const Color(0xFF0F2038) : Colors.white;
    final Color fg = isDark ? Colors.white : const Color(0xFF0F1C3F);

    final Color accent = AppColors.primary;
    final Color onAccent = AppColors.onPrimary;

    return GestureDetector(
      onTap: _openAddHomeDialog,
      child: Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: accent, width: 1.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: HouseGearIcon(
                  color: onAccent,
                  bg: accent, // gear gap = box colour
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Set Up Your Home',
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.arrow_forward_rounded, color: accent, size: 22),
          ],
        ),
      ),
    );
  }

  // ── Shown when user has no registered home (new user / skip-flow) ──
  Widget _buildRegisterHomeCard() {
    return Column(
      children: [
        // ── Add Your Devices card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.primary, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon box (device + plus badge)
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: DevicesIcon(
                          color: AppColors.onPrimary,
                          bg: AppColors.primary,
                          size: 34,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.cardBg, width: 2),
                        ),
                        child: Icon(Icons.add, color: AppColors.onPrimary, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Your Devices',
                style: AppType.sectionTitle.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Register your appliances to manage device details, track warranty information, and request services easily.',
                style: AppType.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _requestScan, // 👉 Scan tab
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.add_rounded, color: AppColors.onPrimary, size: 26),
                  label: Text(
                    'Add Devices',
                    style: TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSetUpHomeButton(),
      ],
    );
  }

  // ── Shown below the Register card when a "Default" home has scanned devices ──
  Widget _buildDefaultHomePreview() {
    final defaultHome = _defaultHome;
    if (defaultHome == null) return const SizedBox.shrink();

    final rooms = (defaultHome['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};
    final allDevices = rooms.values.expand((l) => l).toList();

    if (allDevices.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.flatCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                AppStrings.defaultDevices(allDevices.length),
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(AppStrings.defaultDevicesNote, style: AppText.faintCaption),
          const SizedBox(height: 12),
          ...allDevices.take(5).map((item) {
            final product = item['product']?.toString() ?? AppStrings.appliance;
            final brand = item['brand']?.toString() ?? '';
            final label =
                brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
            final imageUrl = item['imageUrl']?.toString();
            final fallback = Icon(_iconForAppliance(product), size: 14, color: AppColors.textFaint);

            return InkWell(
              onTap: _openDefaultHomeDevices,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (imageUrl != null && imageUrl.isNotEmpty)
                          ? Image.network(imageUrl,
                              fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
                          : fallback,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 18),
                  ],
                ),
              ),
            );
          }),
          if (allDevices.length > 5)
            InkWell(
              onTap: _openDefaultHomeDevices,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  AppStrings.moreCount(allDevices.length - 5),
                  style: TextStyle(
                      color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Removes the stretch/glow overscroll effect so the page never visually
// moves when the user pulls down. Pull-to-refresh spinner still works.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

// ── House + gear icon (Set Up Your Home) ──
class HouseGearIcon extends StatelessWidget {
  final Color color;
  final Color bg; // gear kitta irukkura gap ku button background color
  final double size;
  const HouseGearIcon({super.key, required this.color, required this.bg, this.size = 32});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _HouseGearPainter(color, bg));
}

class _HouseGearPainter extends CustomPainter {
  final Color color;
  final Color bg;
  _HouseGearPainter(this.color, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // roof (wide, slightly overhanging)
    final roof = Path()
      ..moveTo(4, 50)
      ..lineTo(42, 12)
      ..lineTo(80, 50);
    canvas.drawPath(roof, stroke);

    // chimney
    canvas.drawLine(const Offset(64, 24), const Offset(64, 36), stroke);

    // walls: left wall + floor (stops before gear), right wall top part
    final walls = Path()
      ..moveTo(16, 42)
      ..lineTo(16, 88)
      ..lineTo(44, 88)
      ..moveTo(68, 42)
      ..lineTo(68, 50);
    canvas.drawPath(walls, stroke);

    // small inner "F" / window mark
    canvas.drawLine(const Offset(36, 72), const Offset(36, 56), stroke);
    canvas.drawLine(const Offset(36, 56), const Offset(46, 56), stroke);
    canvas.drawLine(const Offset(36, 64), const Offset(44, 64), stroke);

    // gear (bottom-right, overlapping house corner)
    const c = Offset(74, 76);
    canvas.drawCircle(c, 21, Paint()..color = bg); // clear area behind gear

    final gear = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(c, 10, gear);
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * 13, c + d * 19, gear);
    }
  }

  @override
  bool shouldRepaint(covariant _HouseGearPainter old) =>
      old.color != color || old.bg != bg;
}

// ── Monitor + phone icon (Add Your Devices) ──
class DevicesIcon extends StatelessWidget {
  final Color color;
  final Color bg; // icon box background color
  final double size;
  const DevicesIcon({super.key, required this.color, required this.bg, this.size = 32});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _DevicesPainter(color, bg));
}

class _DevicesPainter extends CustomPainter {
  final Color color;
  final Color bg;
  _DevicesPainter(this.color, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // monitor
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(6, 12, 68, 46), const Radius.circular(6)),
      stroke,
    );
    // stand
    canvas.drawLine(const Offset(40, 58), const Offset(40, 74), stroke);
    canvas.drawLine(const Offset(24, 78), const Offset(56, 78), stroke);

    // phone (fill first so monitor line is hidden behind it)
    final phone = RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 38, 30, 50), const Radius.circular(6));
    canvas.drawRRect(phone, Paint()..color = bg);
    canvas.drawRRect(phone, stroke);
    canvas.drawLine(const Offset(70, 79), const Offset(80, 79), stroke);
  }

  @override
  bool shouldRepaint(covariant _DevicesPainter old) =>
      old.color != color || old.bg != bg;
}