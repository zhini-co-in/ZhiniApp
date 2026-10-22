// lib/home_tab.dart
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'address_screen.dart';
import 'constants/api_config.dart';
import 'models/home_model.dart';
import 'room_detail_screen.dart';
import 'service_category_sheet.dart';
import 'services/api_client.dart';
import 'services/device_id_service.dart';
import 'services/entity_update_service.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/confirm_action_dialog.dart';
import 'widgets/light_card.dart';
import 'widgets/room_selector_chips.dart';
import 'widgets/section_header.dart';

// Called whenever HomeTab wants the Scan tab to open. `homeId` is the home
// appliances should be attached to — pass null to make the backend create a
// BRAND NEW home from `address` (used by "Add Home"). Pass an existing
// home's id to add to that home.
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
  final ScanRequest? onScanTap;
  final VoidCallback? onProfileTap;
  final ValueChanged<bool>? onHomeStatusChanged;
  final void Function(String? homeId, String address, String pincode)? onSelectedHomeChanged;

  const HomeTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.onScanTap,
    this.onProfileTap,
    this.onHomeStatusChanged,
    this.onSelectedHomeChanged,
  });

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  bool _loading = true;
  String? _error;
  final _homeBox = Hive.box<HomeModel>('homes');

  bool _fetchInFlight = false;

  // Each entry: { id, address, pincode, members, rooms: {roomKey: [items]}, roomIds }
  List<Map<String, dynamic>> _homes = [];
  int _selectedHomeIndex = 0;

  // Name entered while registering (replaces "Guest" until app restarts).
  String? _nameOverride;
  String get _displayName => _nameOverride ?? widget.name;

  // Locally-created empty rooms, stored PER HOME (key = homeId).
  final Map<String, Map<String, String>> _localExtraRoomsByHome = {};

  String get _homeScopeKey => _currentHomeId ?? 'idx_$_selectedHomeIndex';

  // Always points to the extra rooms of the CURRENTLY selected home only.
  Map<String, String> get _localExtraRooms =>
      _localExtraRoomsByHome.putIfAbsent(_homeScopeKey, () => {});

  // Hidden placeholder room used by AddressScreen to force home creation at
  // signup time. Never shown anywhere in the UI.
  static const String _hiddenSetupRoomKey = '__setup__';

  static const List<String> _suggestedRooms = ['Hall', 'Kitchen', 'Bedroom', 'Bathroom'];

  // ---------------------------------------------------------------------
  // CATALOG DATA
  // ---------------------------------------------------------------------
  static const List<Map<String, dynamic>> _roomTypes = [
    {'key': 'living room', 'label': 'Living room', 'icon': Icons.weekend_rounded, 'color': Color(0xFF4A90E2)},
    {'key': 'kitchen', 'label': 'Kitchen', 'icon': Icons.kitchen_rounded, 'color': Color(0xFFE2B93B)},
    {'key': 'bedroom', 'label': 'Bedroom', 'icon': Icons.bed_rounded, 'color': Color(0xFF9B6BD6)},
    {'key': 'bathroom', 'label': 'Bathroom', 'icon': Icons.bathtub_rounded, 'color': Color(0xFF3BC9DB)},
    {'key': 'utility', 'label': 'Utility', 'icon': Icons.local_laundry_service_rounded, 'color': Color(0xFF4CAF50)},
    {'key': 'study', 'label': 'Study / Office', 'icon': Icons.laptop_mac_rounded, 'color': Color(0xFFB666D2)},
    {'key': 'dining room', 'label': 'Dining room', 'icon': Icons.table_restaurant_rounded, 'color': Color(0xFFE28A3B)},
    {'key': 'custom', 'label': 'Custom', 'icon': Icons.add_rounded, 'color': AppColors.textMuted},
  ];

  static const Map<String, List<String>> _roomNameSuggestions = {
    'living room': ['Living Hall', 'Drawing Room', 'Hall', 'TV Room', 'Front Room'],
    'kitchen': ['Kitchen', 'Modular Kitchen', 'Cook Room'],
    'bedroom': ['Master Bedroom', 'Bedroom 1', 'Bedroom 2', 'Guest Room'],
    'bathroom': ['Bathroom', 'Attached Bath', 'Common Bath'],
    'utility': ['Utility Room', 'Wash Area', 'Store Room'],
    'study': ['Study Room', 'Home Office', 'Work Room'],
    'dining room': ['Dining Room', 'Dining Hall'],
  };

  static const Map<String, List<Map<String, dynamic>>> _quickDeviceSuggestions = {
    'living room': [
      {'label': 'TV', 'icon': Icons.tv_rounded},
      {'label': 'AC', 'icon': Icons.ac_unit_rounded},
      {'label': 'Speaker', 'icon': Icons.speaker_rounded},
      {'label': 'Fan', 'icon': Icons.mode_fan_off_rounded},
      {'label': 'Set top box', 'icon': Icons.settings_input_antenna_rounded},
    ],
    'kitchen': [
      {'label': 'Fridge', 'icon': Icons.kitchen_rounded},
      {'label': 'Mixer', 'icon': Icons.blender_rounded},
      {'label': 'Microwave', 'icon': Icons.microwave_rounded},
      {'label': 'Water Purifier', 'icon': Icons.water_drop_rounded},
    ],
    'bedroom': [
      {'label': 'AC', 'icon': Icons.ac_unit_rounded},
      {'label': 'TV', 'icon': Icons.tv_rounded},
      {'label': 'Fan', 'icon': Icons.mode_fan_off_rounded},
    ],
    'bathroom': [
      {'label': 'Geyser', 'icon': Icons.hot_tub_rounded},
      {'label': 'Exhaust Fan', 'icon': Icons.mode_fan_off_rounded},
    ],
  };

  static const Map<String, IconData> _roomIcons = {
    'hall': Icons.weekend_rounded,
    'kitchen': Icons.kitchen_rounded,
    'bedroom': Icons.bed_rounded,
    'bathroom': Icons.bathtub_rounded,
  };

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

  // Services near you — backed by scrapeHomeServices(serviceType, pincode).
  static const List<Map<String, dynamic>> _serviceCategories = [
    {'label': 'Electrician', 'type': 'electrician', 'icon': Icons.electrical_services_rounded},
    {'label': 'Plumber', 'type': 'plumber', 'icon': Icons.plumbing_rounded},
    {'label': 'AC Service', 'type': 'AC service', 'icon': Icons.ac_unit_rounded},
    {'label': 'Carpenter', 'type': 'carpenter', 'icon': Icons.carpenter_rounded},
    {'label': 'Painter', 'type': 'painter', 'icon': Icons.format_paint_rounded},
    {'label': 'Pest Control', 'type': 'pest control', 'icon': Icons.pest_control_rounded},
  ];

  static const int _maxRoomsOnHome = 4;

  // serviceType -> provider count, shown as "X nearby".
  final Map<String, int> _serviceCounts = {};
  Future<String?>? _gpsQueryCache;

  @override
  void initState() {
    super.initState();
    _fetchAppliances();
    _prefetchServiceCounts();
  }

  // Called by MainShell when the Home tab is tapped.
  Future<void> refresh() async {
    while (_fetchInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _fetchAppliances();
    if (!mounted) return;
    _gpsQueryCache = null;
    setState(() => _serviceCounts.clear());
    _prefetchServiceCounts();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------
  // SERVICES NEAR YOU — data
  // ---------------------------------------------------------------------
  // Fetches every category IN PARALLEL so the "X nearby" counts are fast.
  void _prefetchServiceCounts() async {
    final futures = _serviceCategories.map((cat) async {
      final type = cat['type'] as String;
      final list = await _fetchHomeServicesFor(type);
      if (mounted) setState(() => _serviceCounts[type] = list.length);
    });
    await Future.wait(futures);
  }

  // Defaults to the home's pincode; falls back to live GPS when there's no
  // pincode or when forced.
  Future<List<Map<String, dynamic>>> _fetchHomeServicesFor(
    String serviceType, {
    String? pincodeOverride,
    bool forceGps = false,
  }) async {
    try {
      String? locationQuery;
      if (!forceGps) {
        final pincode = pincodeOverride ?? _currentPincode;
        if (pincode.isNotEmpty) {
          locationQuery = '&pincode=${Uri.encodeQueryComponent(pincode)}';
        }
      }
      locationQuery ??= await _buildGpsLocationQuery();
      if (locationQuery == null) return [];

      final response = await ApiClient.post(
        '${ApiConfig.homeServicesUrl}'
        '?serviceType=${Uri.encodeQueryComponent(serviceType)}'
        '$locationQuery',
      );

      debugPrint('🔧 Home services ($serviceType) status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('❌ Home services fetch error ($serviceType): $e');
    }
    return [];
  }

  Future<String?> _buildGpsLocationQuery() {
    final future = _gpsQueryCache ??= _resolveGpsLocationQuery();
    // Don't cache a failure, so the next call can retry.
    future.then((v) {
      if (v == null) _gpsQueryCache = null;
    });
    return future;
  }

  Future<String?> _resolveGpsLocationQuery() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;
      return '&latitude=${position.latitude}&longitude=${position.longitude}';
    } catch (e) {
      debugPrint('❌ Location fetch error (home services): $e');
      return null;
    }
  }

  void _openServiceCategorySheet(Map<String, dynamic> category) {
    final type = category['type'] as String;
    final label = category['label'] as String;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (_) => ServiceCategorySheet(
        label: label,
        fetchServices: () => _fetchHomeServicesFor(type),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ICON HELPERS
  // ---------------------------------------------------------------------
  IconData _iconForRoom(String room) =>
      _roomIcons[room.toLowerCase()] ?? Icons.door_front_door_rounded;

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

    // Remember the selected home BEFORE the cache replaces _homes.
    final selectedIdBefore = _currentHomeId;
    final selectedAddressBefore = _currentHome?['address']?.toString().trim().toLowerCase();
    final selectedPincodeBefore = _currentHome?['pincode']?.toString().trim();

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
          if (selectedIdBefore != null) {
            final i = _homes.indexWhere((h) => h['id']?.toString() == selectedIdBefore);
            if (i != -1) _selectedHomeIndex = i;
          }
          if (_selectedHomeIndex >= _homes.length) _selectedHomeIndex = 0;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    }

    try {
      final plainMobile = ApiConfig.stripCountryCode(widget.mobileNumber);
      var url = '${ApiConfig.submissionSearchUrl}?mobile=$plainMobile';
      if (isSingleHomeRefresh) url += '&homeId=$homeId';

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
                rooms[key] = devicesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

                final rid = (roomObj['_id'] ?? roomObj['roomId'])?.toString();
                if (rid != null && rid.isNotEmpty) roomIds[key] = rid;
              }
            } else if (roomsRaw is Map) {
              // Flat-map fallback has no per-room id; delete falls back to local-only.
              roomsRaw.forEach((key, value) {
                if (value is List) {
                  if (key.toString().toLowerCase() == _hiddenSetupRoomKey) return;
                  rooms[key.toString().toLowerCase()] =
                      value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
              'rooms': rooms,
              'roomIds': roomIds,
              'members': members,
            };
          }).toList();

          final dedupedHomes = _dedupeHomes(parsedHomes);

          if (isSingleHomeRefresh) {
            if (dedupedHomes.isNotEmpty && mounted) {
              final updated = dedupedHomes.firstWhere(
                (h) => h['id']?.toString() == homeId,
                orElse: () => dedupedHomes.first,
              );
              final idx = _homes.indexWhere((h) => h['id']?.toString() == homeId);
              setState(() {
                if (idx != -1) {
                  _homes[idx] = updated;
                } else {
                  _homes.add(updated);
                }
                final updatedRooms = updated['rooms'] as Map<String, List<Map<String, dynamic>>>;
                _localExtraRoomsByHome[homeId]
                    ?.removeWhere((key, _) => updatedRooms.containsKey(key));
              });
              await _homeBox.clear();
              for (final h in _homes) {
                await _homeBox.add(HomeModel.fromMap(h));
              }
            }
            return;
          }

          // Full refresh path.
          await _homeBox.clear();
          for (final h in dedupedHomes) {
            await _homeBox.add(HomeModel.fromMap(h));
          }

          final previousSelectedId = selectedIdBefore;
          final previousAddress = selectedAddressBefore;
          final previousPincode = selectedPincodeBefore;
          final previousHomesSnapshot = List<Map<String, dynamic>>.from(_homes);

          if (mounted) {
            setState(() {
              _homes = _stableOrderHomes(previousHomesSnapshot, dedupedHomes);

              int idx = -1;
              if (previousSelectedId != null) {
                idx = _homes.indexWhere((h) => h['id']?.toString() == previousSelectedId);
              }
              if (idx == -1 && previousAddress != null && previousAddress.isNotEmpty) {
                idx = _homes.indexWhere((h) =>
                    h['address']?.toString().trim().toLowerCase() == previousAddress &&
                    h['pincode']?.toString().trim() == previousPincode);
              }

              if (idx != -1) {
                _selectedHomeIndex = idx;
              } else if (_selectedHomeIndex >= _homes.length) {
                _selectedHomeIndex = 0;
              }

              // Drop a local-extra room once the backend actually has it (per home).
              for (final h in _homes) {
                final hid = h['id']?.toString();
                if (hid == null) continue;
                final hRooms = h['rooms'] as Map<String, List<Map<String, dynamic>>>;
                _localExtraRoomsByHome[hid]?.removeWhere((key, _) => hRooms.containsKey(key));
              }

              _loading = false;
            });
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
            _error = 'Could not load your home. Pull down to retry.';
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
  Map<String, dynamic>? get _currentHome => _homes.isEmpty ? null : _homes[_selectedHomeIndex];

  Map<String, List<Map<String, dynamic>>> get _currentRooms =>
      (_currentHome?['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};

  Map<String, String> get _currentRoomIds =>
      (_currentHome?['roomIds'] as Map<String, String>?) ?? {};

  String? get _currentHomeId => _currentHome?['id']?.toString();
  String get _currentAddress => _currentHome?['address']?.toString() ?? widget.address;
  String get _currentPincode => _currentHome?['pincode']?.toString() ?? widget.pincode;

  void _notifySelectedHome() {
    widget.onSelectedHomeChanged?.call(_currentHomeId, _currentAddress, _currentPincode);
  }

  String _homeLabel(Map<String, dynamic> home, int index) {
    final address = home['address']?.toString() ?? '';
    final firstPart = address.split(',').first.trim();
    return firstPart.isNotEmpty ? firstPart : 'Home ${index + 1}';
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

  List<MapEntry<String, String>> get _displayRooms {
    final entries = <MapEntry<String, String>>[];
    final realKeys = _currentRooms.keys.toList()..sort();
    for (final key in realKeys) {
      final display = key.isNotEmpty ? '${key[0].toUpperCase()}${key.substring(1)}' : key;
      entries.add(MapEntry(key, display));
    }
    _localExtraRooms.forEach((key, display) {
      if (!_currentRooms.containsKey(key)) entries.add(MapEntry(key, display));
    });
    return entries;
  }

  void _requestScan() {
    widget.onScanTap?.call(
      homeId: _currentHomeId,
      address: _currentAddress,
      pincode: _currentPincode,
      knownRooms: _displayRooms.map((e) => e.value).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------
  Map<String, int> _computeStats() {
    int devices = 0;
    int warrantyOk = 0;
    int attention = 0;
    final now = DateTime.now();

    _currentRooms.forEach((_, items) {
      for (final item in items) {
        devices++;
        final expiry = WarrantyUtils.parseExpiry(
          item['warranty']?.toString(),
          referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
        );
        if (expiry != null && expiry.isAfter(now)) {
          warrantyOk++;
        } else {
          attention++;
        }
      }
    });

    return {
      'devices': devices,
      'warranty': warrantyOk,
      'attention': attention,
      'rooms': _currentRooms.length,
    };
  }

  // ---------------------------------------------------------------------
  // DELETE ROOM
  // ---------------------------------------------------------------------
  Future<bool> _submitDeleteRoom(String homeId, String roomId) async {
    try {
      final response = await ApiClient.delete(
        ApiConfig.deleteRoomUrl(homeId),
        body: {'roomId': roomId, 'homeId': homeId},
      );
      debugPrint('🗑️ Delete room status: ${response.statusCode}');
      if (!mounted) return false;

      if (response.statusCode == 200) return true;
      final data = jsonDecode(response.body);
      _snack(data['message']?.toString() ?? 'Could not delete room.');
      return false;
    } catch (e) {
      debugPrint('❌ Delete room error: $e');
      _snack('Network error. Try again.');
      return false;
    }
  }

  // Via backend (if it has a real roomId) or purely client-side (local empty room).
  Future<void> _confirmDeleteRoom(String roomKey, String displayName) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Delete room?',
      content: '$displayName and any devices in it will be removed. This cannot be undone.',
    );
    if (ok != true) return;

    final homeId = _currentHomeId;
    final roomId = _currentRoomIds[roomKey];

    if (homeId == null || roomId == null) {
      setState(() => _localExtraRooms.remove(roomKey));
      _snack('$displayName removed ✅');
      return;
    }

    final success = await _submitDeleteRoom(homeId, roomId);
    if (success) {
      setState(() => _localExtraRooms.remove(roomKey));
      _snack('$displayName removed ✅');
      _fetchAppliances(homeId: homeId);
    }
  }

  // ---------------------------------------------------------------------
  // ROOM DETAIL
  // ---------------------------------------------------------------------
  void _openRoomDetail(String roomKey, String displayName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(
          roomKey: roomKey,
          roomName: displayName,
          items: _currentRooms[roomKey] ?? [],
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

  // Room that lives in the "Default" home (skip-flow).
  void _openDefaultRoomDetail(String roomKey) {
    final dh = _defaultHome;
    if (dh == null) return;
    final rooms = (dh['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};
    final displayName =
        roomKey.isNotEmpty ? '${roomKey[0].toUpperCase()}${roomKey.substring(1)}' : roomKey;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(
          roomKey: roomKey,
          roomName: displayName,
          items: rooms[roomKey] ?? [],
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
  // ADD A ROOM — 3-step guided flow
  // ---------------------------------------------------------------------
  Widget _dialogHeader(BuildContext dialogContext, String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppText.dialogTitle),
        InkWell(
          onTap: () => Navigator.pop(dialogContext),
          borderRadius: BorderRadius.circular(20),
          child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
        ),
      ],
    );
  }

  void _openAddRoomDialog() {
    int step = 0;
    Map<String, dynamic>? selectedType;
    final nameController = TextEditingController();
    String createdDisplay = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget dots() {
              return Row(
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.only(right: 5),
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? AppColors.primary : AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              );
            }

            // ---------------- STEP 1 : Pick room type ----------------
            Widget buildStep1() {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogHeader(dialogContext, 'Add a room'),
                  const SizedBox(height: 2),
                  const Text('Choose the room type', style: AppText.faintCaption),
                  const SizedBox(height: 10),
                  dots(),
                  const SizedBox(height: 16),
                  const Text('COMMON ROOMS', style: AppText.label),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _roomTypes.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.5,
                    ),
                    itemBuilder: (context, i) {
                      final type = _roomTypes[i];
                      final isSelected = selectedType?['key'] == type['key'];
                      final color = type['color'] as Color;
                      return InkWell(
                        onTap: () => setDialogState(() => selectedType = type),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha: 0.12) : AppColors.cardBgAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? color : AppColors.borderSubtle,
                              width: isSelected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(type['icon'] as IconData, color: color, size: 18),
                              ),
                              const SizedBox(height: 8),
                              Text(type['label'] as String,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: AppDecor.primaryButton,
                      onPressed: selectedType == null
                          ? null
                          : () {
                              final key = selectedType!['key'] as String;
                              final suggestions = _roomNameSuggestions[key];
                              nameController.text =
                                  (key != 'custom' && suggestions != null && suggestions.isNotEmpty)
                                      ? suggestions.first
                                      : '';
                              setDialogState(() => step = 1);
                            },
                      child: const Text('Continue', style: AppText.button),
                    ),
                  ),
                ],
              );
            }

            // ---------------- STEP 2 : Name the room ----------------
            Widget buildStep2() {
              final type = selectedType!;
              final color = type['color'] as Color;
              final key = type['key'] as String;
              final suggestions = key == 'custom' ? <String>[] : (_roomNameSuggestions[key] ?? []);
              final homeLabel =
                  _currentAddress.isNotEmpty ? _currentAddress.split(',').first.trim() : 'Home';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogHeader(dialogContext, 'Name this room'),
                  const SizedBox(height: 2),
                  Text('${type['label']} selected', style: AppText.faintCaption),
                  const SizedBox(height: 10),
                  dots(),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                          child: Icon(type['icon'] as IconData, color: color, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type['label'] as String,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                              Text('$homeLabel home', style: AppText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('ROOM NAME', style: AppText.label),
                  const SizedBox(height: 8),
                  AppDialogField(controller: nameController, hint: 'e.g. Living Hall'),
                  const SizedBox(height: 4),
                  const Text('Give it a name that helps you identify it quickly',
                      style: AppText.faintCaption),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('QUICK SUGGESTIONS', style: AppText.labelMuted),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions.map((s) {
                        final isChosen = nameController.text.trim() == s;
                        return InkWell(
                          onTap: () => setDialogState(() => nameController.text = s),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isChosen ? AppColors.primarySoft : AppColors.cardBgAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isChosen ? AppColors.primary : AppColors.borderSubtle),
                            ),
                            child: Text(s,
                                style: TextStyle(
                                    color: isChosen ? AppColors.primary : AppColors.textSecondary,
                                    fontSize: 12.5)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardBgAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.home_outlined, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Adding to: $_currentAddress',
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: AppDecor.primaryButton,
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          _snack('Enter a room name.');
                          return;
                        }
                        final roomKey = name.toLowerCase();
                        if (_currentRooms.containsKey(roomKey) || _localExtraRooms.containsKey(roomKey)) {
                          _snack('This room already exists.');
                          return;
                        }
                        createdDisplay = name;
                        setState(() => _localExtraRooms[roomKey] = name);
                        setDialogState(() => step = 2);
                      },
                      child: const Text('Create room', style: AppText.button),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => setDialogState(() => step = 0),
                      child: const Text('← Back', style: AppText.cancelAction),
                    ),
                  ),
                ],
              );
            }

            // ---------------- STEP 3 : Room added / quick devices ----------------
            Widget buildStep3() {
              final type = selectedType!;
              final key = type['key'] as String;
              final devices = _quickDeviceSuggestions[key] ??
                  const [
                    {'label': 'Appliance', 'icon': Icons.devices_other_rounded},
                  ];
              final homeLabel =
                  _currentAddress.isNotEmpty ? _currentAddress.split(',').first.trim() : 'Home';
              final who = (_displayName.isNotEmpty && _displayName.toLowerCase() != 'guest')
                  ? _displayName
                  : 'You';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogHeader(dialogContext, 'Room added'),
                  const SizedBox(height: 2),
                  Text('$homeLabel — $who', style: AppText.faintCaption),
                  const SizedBox(height: 10),
                  dots(),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$createdDisplay created',
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('$homeLabel home · 0 devices so far', style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Suggested devices for this room',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  // Suggestions only: not tappable.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: devices.map((d) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.cardBgAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(d['icon'] as IconData, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(d['label'] as String,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: AppDecor.primaryOutlinedButton,
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _openManualAddDialog(initialRoom: createdDisplay);
                      },
                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
                      label: const Text('Add manually',
                          style: TextStyle(
                              color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: AppDecor.primaryButton,
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _requestScan();
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppColors.onPrimary),
                      label: const Text('Scan and add first device', style: AppText.button),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Done — go to home', style: AppText.cancelAction),
                    ),
                  ),
                ],
              );
            }

            return Dialog(
              backgroundColor: AppColors.cardBg,
              shape: AppDecor.dialogShape,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(
                        key: ValueKey(step),
                        child: step == 0 ? buildStep1() : (step == 1 ? buildStep2() : buildStep3()),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressScreen(
          mobileNumber: widget.mobileNumber,
          isAddingHome: true,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final newAddress = result['address'] ?? '';
    final newPincode = result['pincode'] ?? '';
    if (newAddress.isEmpty) return;
    final newName = (result['name'] ?? '').toString().trim();
    if (newName.isNotEmpty) setState(() => _nameOverride = newName);

    // ---------- UPDATE the Default (Guest) home ----------
    if (existingDefaultId != null) {
      debugPrint('✏️ Updating Default home $existingDefaultId -> $newAddress');
      final ok = await _submitAddressUpdate(existingDefaultId, newAddress, newPincode);
      if (ok && mounted) {
        if (newName.isNotEmpty) {
          setState(() => _nameOverride = newName);
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
          if (idx != -1) _selectedHomeIndex = idx;
          _serviceCounts.clear();
        });
        await SessionManager.updateHomeId(existingDefaultId);
        _notifySelectedHome();
        _prefetchServiceCounts();
      }
      return;
    }

    // ---------- CREATE a brand-new home ----------
    debugPrint('🆕 Creating NEW home -> $newAddress');
    final firstPart = newAddress.split(',').first.trim();
    final newHomeId = await _createNewHomeRecord(
      address: newAddress,
      pincode: newPincode,
      name: newName.isNotEmpty ? newName : _displayName,
      homeName: firstPart.isNotEmpty ? firstPart : 'Home ${_homes.length + 1}',
    );

    if (newHomeId == null) {
      _snack('Could not create the new home. Try again.');
      return;
    }

    while (_fetchInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _fetchAppliances();
    if (!mounted) return;
    setState(() {
      final idx = _homes.indexWhere((h) => h['id']?.toString() == newHomeId);
      _selectedHomeIndex = idx != -1 ? idx : _homes.length - 1;
      _serviceCounts.clear();
    });
    await SessionManager.updateHomeId(newHomeId);
    _notifySelectedHome();
    _prefetchServiceCounts();
    _snack('Home added ✅');
  }

  // Creates a brand-new home on the backend and returns its homeId.
  Future<String?> _createNewHomeRecord({
    required String address,
    required String pincode,
    required String name,
    required String homeName,
  }) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final deviceId = await DeviceIdService.getDeviceId();
      final fcmToken = await ApiClient.safeFcmToken();

      if (authToken == null) {
        debugPrint('❌ No Firebase auth token — user not signed in?');
        _snack('Please sign in again to add a home.');
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

  Future<bool> _submitAddressUpdate(String homeId, String address, String pincode) async {
    final result = await EntityUpdateService.update(
      homeId: homeId,
      address: address,
      pincode: pincode.isNotEmpty ? pincode : null,
    );

    if (!mounted) return false;

    _snack(result['success'] == true
        ? 'Address updated successfully ✅'
        : (result['message']?.toString() ?? 'Failed to update address'));
    return result['success'] == true;
  }

  // ---------------------------------------------------------------------
  // MANUAL ADD — product / brand / warranty / room, no camera needed.
  // ---------------------------------------------------------------------
  void _openManualAddDialog({String? initialRoom}) {
    final productController = TextEditingController();
    final brandController = TextEditingController();
    final warrantyController = TextEditingController();
    String selectedRoom = initialRoom ?? 'Hall';
    bool isCustomRoom = false;
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary, size: 20),
                        ),
                      ),
                      const Text('Add Appliance', style: AppText.dialogTitle),
                    ],
                  ),
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 20),
                          SizedBox(width: 4),
                          Text('Scan', style: AppText.linkAction),
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
                      hint: 'Product name (e.g. Refrigerator)',
                    ),
                    const SizedBox(height: 10),
                    AppDialogField(controller: brandController, hint: 'Brand (optional)'),
                    const SizedBox(height: 10),
                    AppDialogField(
                        controller: warrantyController, hint: 'Warranty (e.g. 2 Years, optional)'),
                    const SizedBox(height: 12),
                    const Text('Room', style: AppText.faintCaption),
                    const SizedBox(height: 8),
                    RoomSelectorChips(
                      rooms: _displayRooms.map((e) => e.value).toSet().union(_suggestedRooms.toSet()),
                      selectedRoom: selectedRoom,
                      isCustomRoom: isCustomRoom,
                      onSelectRoom: (room) => setDialogState(() {
                        selectedRoom = room;
                        isCustomRoom = false;
                      }),
                      onTapOther: () async {
                        final name = await showCustomRoomNameDialog(
                          dialogContext,
                          initial: isCustomRoom ? selectedRoom : '',
                        );
                        if (name != null) {
                          setDialogState(() {
                            selectedRoom = name;
                            isCustomRoom = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: AppText.cancelAction),
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
                            room: selectedRoom,
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
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2),
                        )
                      : const Text('Add appliance', style: TextStyle(color: AppColors.onPrimary)),
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
    required String room,
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
          _snack('Could not set up your home. Try again.');
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
      request.fields['roomName'] = room;
      request.fields['name'] = _displayName;

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      debugPrint('📦 Manual submit status: ${response.statusCode}');

      if (!mounted) return false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _snack('$product added ✅');
        return true;
      }
      final data = jsonDecode(response.body);
      _snack(data['message']?.toString() ?? 'Could not add appliance. Try again.');
      return false;
    } catch (e) {
      debugPrint('❌ Manual submit error: $e');
      _snack('Network error. Try again.');
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // ALL ROOMS SHEET (dark sheet, dark room cards)
  // ---------------------------------------------------------------------
  void _openAllRoomsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        final rooms = _displayRooms;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('All rooms (${rooms.length})', style: AppText.dialogTitle),
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Tap to open · long-press to delete', style: AppText.faintCaption),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 112,
                    ),
                    itemCount: rooms.length,
                    itemBuilder: (context, i) => _roomCard(
                      rooms[i].key,
                      rooms[i].value,
                      onBeforeOpen: () => Navigator.pop(sheetContext),
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

  // Compact dark room card used inside the "All rooms" sheet.
  Widget _roomCard(String roomKey, String displayName, {VoidCallback? onBeforeOpen}) {
    final items = _currentRooms[roomKey] ?? [];
    final first = items.isNotEmpty ? items.first : null;
    final extra = items.length - 1;
    final firstProduct = first?['product']?.toString() ?? '';
    final firstImage = first?['imageUrl']?.toString();

    return InkWell(
      onTap: () {
        onBeforeOpen?.call();
        _openRoomDetail(roomKey, displayName);
      },
      onLongPress: () => _confirmDeleteRoom(roomKey, displayName),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_iconForRoom(roomKey), color: AppColors.primary, size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('${items.length} appliance${items.length == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 15),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Divider(height: 1, color: AppColors.borderSubtle),
            ),
            if (first == null)
              const Text('No appliances yet',
                  style: TextStyle(color: AppColors.textDisabled, fontSize: 10.5))
            else
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: (firstImage != null && firstImage.isNotEmpty)
                          ? Image.network(
                              firstImage,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(_iconForAppliance(firstProduct),
                                  size: 14, color: AppColors.textFaint),
                            )
                          : Icon(_iconForAppliance(firstProduct), size: 14, color: AppColors.textFaint),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(firstProduct,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                  ),
                  if (extra > 0)
                    Text('+$extra',
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // BUILD
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    final stats = _loading ? null : _computeStats();
    final hasHome = !_loading && _hasRegisteredHome;

    if (!_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onHomeStatusChanged?.call(hasHome);
        _notifySelectedHome();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.lightPrimary))
            : RefreshIndicator(
                color: AppColors.lightPrimary,
                onRefresh: () => _currentHomeId != null
                    ? _fetchAppliances(homeId: _currentHomeId)
                    : _fetchAppliances(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                            )
                          else if (!hasHome) ...[
                            _buildRegisterHomeCard(),
                            _buildDefaultHomePreview(),
                            const SizedBox(height: 28),
                            _buildServicesNearYou(),
                          ] else ...[
                            SectionHeader('Buildings', onManage: widget.onProfileTap),
                            const SizedBox(height: 12),
                            _buildHomeSwitcher(),
                            const SizedBox(height: 20),
                            _buildStatsRow(stats!),
                            const SizedBox(height: 24),
                            SectionHeader('Rooms (${stats['rooms']})',
                                actionLabel: 'View all', onManage: _openAllRoomsSheet),
                            const SizedBox(height: 12),
                            _buildRoomsList(),
                            const SizedBox(height: 12),
                            _buildAddRoomButton(),
                            const SizedBox(height: 28),
                            _buildServicesNearYou(),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── HEADER (logo + avatar + search + hero) ──
  Widget _buildHeader() {
    final hasName = _displayName.isNotEmpty && _displayName.toLowerCase() != 'guest';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppDecor.lightHeaderGradient),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'zhini',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.lightSurface,
                    child: Text(
                      hasName ? _displayName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        color: AppColors.lightPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search devices, rooms or services',
                  hintStyle: TextStyle(color: AppColors.lightHint, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.lightHint),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned(
                    left: 0,
                    top: 12,
                    right: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your home\nin control', style: AppText.lightHeroTitle),
                        SizedBox(height: 8),
                        Text('Monitor, manage and keep\neverything running smoothly.',
                            style: AppText.lightHeroSubtitle),
                      ],
                    ),
                  ),
                  Positioned(
                    right: -16,
                    top: -4,
                    bottom: -8,
                    width: 175,
                    child: Image.asset(
                      'assets/images/house1.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Building chips ──
  Widget _buildHomeSwitcher() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _homes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final selected = index == _selectedHomeIndex;
          final label = _homeLabel(_homes[index], index);

          return GestureDetector(
            onTap: () {
              setState(() => _selectedHomeIndex = index);
              _notifySelectedHome();
              _prefetchServiceCounts();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.lightPrimary : AppColors.lightBorderStrong,
                  width: selected ? 1.8 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.lightPrimary.withValues(alpha: 0.12),
                          blurRadius: 8,
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.apartment_rounded,
                    size: 18,
                    color: selected ? AppColors.lightPrimary : AppColors.lightTextMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.lightPrimary : AppColors.lightTextSoft,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.lightPrimary),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Stats ──
  Widget _buildStatsRow(Map<String, int> stats) {
    return Row(
      children: [
        _statCard(Icons.devices_other_rounded, AppColors.lightPrimary, '${stats['devices']}', 'Devices'),
        const SizedBox(width: 10),
        _statCard(Icons.meeting_room_outlined, AppColors.lightPurple, '${stats['rooms']}', 'Rooms'),
        const SizedBox(width: 10),
        _statCard(Icons.verified_user_outlined, AppColors.lightSuccess, '${stats['warranty']}', 'Warranty'),
        const SizedBox(width: 10),
        _statCard(Icons.warning_amber_rounded, AppColors.lightWarning, '${stats['attention']}', 'Attention',
            highlight: (stats['attention'] ?? 0) > 0),
      ],
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label, {bool highlight = false}) {
    return Expanded(
      child: LightCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        borderColor: highlight ? color.withValues(alpha: 0.4) : AppColors.lightBorder,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.lightTextDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.lightTextMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rooms (horizontal list, first few) ──
  Widget _buildRoomsList() {
    final rooms = _displayRooms.take(_maxRoomsOnHome).toList();
    if (rooms.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final key = rooms[i].key;
          final name = rooms[i].value;
          final count = (_currentRooms[key] ?? []).length;

          return LightCard(
            width: 148,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => _openRoomDetail(key, name),
            onLongPress: () => _confirmDeleteRoom(key, name),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: AppDecor.lightIconBox(),
                  child: Icon(_iconForRoom(key), color: AppColors.lightPrimary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.lightCardTitle),
                      const SizedBox(height: 2),
                      Text('$count device${count == 1 ? '' : 's'}', style: AppText.lightCaption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.lightChevron, size: 18),
              ],
            ),
          );
        },
      ),
    );
  }

  // NOTE: the old UI had no reachable "Add room" button. Delete this widget
  // and its call in build() if you do not want it on the Home screen.
  Widget _buildAddRoomButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openAddRoomDialog,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.lightPrimary, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.lightPrimary, size: 18),
        label: const Text('Add New Room', style: AppText.lightLink),
      ),
    );
  }

  // ── Services near you ──
  Widget _buildServicesNearYou() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Services near you'),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _serviceCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final cat = _serviceCategories[i];
              final count = _serviceCounts[cat['type'] as String];
              return LightCard(
                width: 95,
                onTap: () => _openServiceCategorySheet(cat),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(cat['icon'] as IconData, color: AppColors.lightPrimary, size: 22),
                    const Spacer(),
                    Text(cat['label'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.lightCardTitle),
                    Text(count == null ? '...' : '$count nearby', style: AppText.lightSuccessCaption),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _infoCard(Icons.build_rounded, AppColors.lightPrimary, 'Installation',
                  'Get expert setup at your home'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _infoCard(Icons.headset_mic_rounded, AppColors.lightPurple, 'Support',
                  'Quick help, anytime'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, Color color, String title, String subtitle) {
    return LightCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.lightCardTitle),
                Text(subtitle, style: AppText.lightCaption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.lightChevron, size: 18),
        ],
      ),
    );
  }

  // ── Shown instead of rooms/stats when user has no registered home (skip-flow) ──
  Widget _buildRegisterHomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecor.flatCard(borderColor: AppColors.primaryBorder.withValues(alpha: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_home_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 14),
          const Text(
            'Set up your home',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add your address to start tracking appliances, warranties, and get matched with nearby services.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openAddHomeDialog,
              style: AppDecor.primaryButton,
              icon: const Icon(Icons.home_rounded, size: 18, color: AppColors.onPrimary),
              label: const Text(
                'Register',
                style: TextStyle(color: AppColors.onPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shown below the Register card when a "Default" home has scanned devices ──
  Widget _buildDefaultHomePreview() {
    final defaultHome = _defaultHome;
    if (defaultHome == null) return const SizedBox.shrink();

    final rooms = (defaultHome['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};
    final allDevices = <MapEntry<String, Map<String, dynamic>>>[];
    rooms.forEach((roomKey, items) {
      for (final it in items) {
        allDevices.add(MapEntry(roomKey, it));
      }
    });

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
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Default devices (${allDevices.length})',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('These will move into your home once you register.', style: AppText.faintCaption),
          const SizedBox(height: 12),
          ...allDevices.take(5).map((entry) {
            final item = entry.value;
            final product = item['product']?.toString() ?? 'Appliance';
            final brand = item['brand']?.toString() ?? '';
            final label =
                brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
            final imageUrl = item['imageUrl']?.toString();
            final fallback = Icon(_iconForAppliance(product), size: 14, color: AppColors.textFaint);

            return InkWell(
              onTap: () => _openDefaultRoomDetail(entry.key),
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
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 18),
                  ],
                ),
              ),
            );
          }),
          if (allDevices.length > 5)
            InkWell(
              onTap: () => _openDefaultRoomDetail(allDevices.first.key),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${allDevices.length - 5} more',
                  style: const TextStyle(
                      color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}