// lib/home_tab.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'constants/api_config.dart';
import 'services/session_manager.dart';
import 'login_screen.dart';
import 'scan_tab.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/home_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'services/entity_update_service.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/confirm_action_dialog.dart';
import 'widgets/room_selector_chips.dart';
import 'widgets/service_provider_card.dart';
import 'my_tickets_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'address_screen.dart'; // 👈 NEW

// Called whenever HomeTab wants the Scan tab to open. `homeId` is the home
// appliances should be attached to — pass null to make the backend create a
// BRAND NEW home from `address` (used by "Add Home"). Pass an existing
// home's id to add to that home (used by the normal scan bar and the
// per-room scan button, and by the home switcher).
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

  const HomeTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.onScanTap,
    this.onProfileTap,
    this.onHomeStatusChanged,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _loading = true;
  String? _error;
  final _homeBox = Hive.box<HomeModel>('homes');
  final bool _isAddingHome = false;

   bool _fetchInFlight = false;

  // Each entry: { id, address, pincode, members: [{name, mobile}], rooms: {roomKey: [items]} }
  List<Map<String, dynamic>> _homes = [];
  int _selectedHomeIndex = 0;

  // Rooms created locally via "Add Room" that don't have any appliances in
  // the backend yet, scoped to the currently selected home.
  final Map<String, String> _localExtraRooms = {};

  // Hidden placeholder room used by AddressScreen to force home creation at
  // signup time (before the user has scanned any real appliance). This
  // should never be shown in the rooms grid, room switcher, stats, or
  // alerts — it's purely a backend bookkeeping artifact.
  static const String _hiddenSetupRoomKey = '__setup__';

  static const List<String> _suggestedRooms = ['Hall', 'Kitchen', 'Bedroom', 'Bathroom'];

  // ---------------------------------------------------------------------
  // ADD-A-ROOM 3-STEP FLOW — catalog data
  // (Step 1: pick a room type, Step 2: name the room, Step 3: room added +
  // quick device suggestions.)
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

  // ---------------------------------------------------------------------
  // SERVICES NEAR YOU — categories shown as cards, backed by
  // scrapeHomeServices(serviceType, pincode) on the backend.
  // ---------------------------------------------------------------------
  static const List<Map<String, dynamic>> _serviceCategories = [
    {'label': 'Electrician', 'type': 'electrician', 'icon': Icons.electrical_services_rounded},
    {'label': 'Plumber', 'type': 'plumber', 'icon': Icons.plumbing_rounded},
    {'label': 'AC Service', 'type': 'AC service', 'icon': Icons.ac_unit_rounded},
    {'label': 'Carpenter', 'type': 'carpenter', 'icon': Icons.carpenter_rounded},
    {'label': 'Painter', 'type': 'painter', 'icon': Icons.format_paint_rounded},
    {'label': 'Pest Control', 'type': 'pest control', 'icon': Icons.pest_control_rounded},
  ];

  // serviceType -> fetched provider list (cached so re-opening a category
  // sheet doesn't re-hit the API every time).
  final Map<String, int> _serviceCounts = {};
  // serviceType -> provider count, shown as "X nearby" on each category card.

  @override
  void initState() {
    super.initState();
    _fetchAppliances();
    _prefetchServiceCounts();
  }

  // Kicks off a fetch for every category IN PARALLEL so the "X nearby"
  // counts are ready fast, instead of waiting for each category one by one.
  void _prefetchServiceCounts() async {
    final futures = _serviceCategories.map((cat) async {
      final type = cat['type'] as String;
      final list = await _fetchHomeServicesFor(type);
      if (mounted) setState(() => _serviceCounts[type] = list.length);
    });
    await Future.wait(futures);
  }

// Single source of truth for the nearby-services fetch. Defaults to the
  // home's saved pincode; falls back to live GPS lat/long when there's no
  // pincode (e.g. a home created via AddressScreen's "Skip" flow) or when
  // the sheet explicitly asks for GPS / a manually-entered pincode.
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

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.homeServicesUrl}'
          '?serviceType=${Uri.encodeQueryComponent(serviceType)}'
          '$locationQuery',
        ),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );

      debugPrint('🔧 Home services ($serviceType) status: ${response.statusCode}');
      debugPrint('🔧 Home services ($serviceType) body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          // Backend already caps this at top 20 rated providers.
          return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('❌ Home services fetch error ($serviceType): $e');
    }
    return [];
  }

  // Silent GPS fetch — no fresh permission prompt in most cases since
  // location is expected to already be tracked/permitted elsewhere in
  // the app. Returns null (caller shows "no results") if location can't
  // be resolved at all.
  Future<String?> _buildGpsLocationQuery() async {
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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
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
      builder: (sheetContext) {
        return _ServiceCategorySheet(
          label: label,
          fetchServices: () => _fetchHomeServicesFor(type),
        );
      },
    );
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('Call launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not start call.')));
      }
    }
  }

  Future<void> _openMapDirections(String address) async {
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Directions launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open maps.')));
      }
    }
  }

  Widget _buildServicesNearYou() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('SERVICES NEAR YOU'),
        const SizedBox(height: 12),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _serviceCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final cat = _serviceCategories[index];
              final type = cat['type'] as String;
              return _serviceCategoryCard(
                icon: cat['icon'] as IconData,
                label: cat['label'] as String,
                count: _serviceCounts[type],
                onTap: () => _openServiceCategorySheet(cat),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _serviceCategoryCard({
    required IconData icon,
    required String label,
    required int? count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: AppDecor.flatCard(radius: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              count == null ? '...' : '$count nearby',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForRoom(String room) => _roomIcons[room.toLowerCase()] ?? Icons.door_front_door_rounded;

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

  // 1. Cache-ல இருந்து instant ஆ காட்டு — full refresh-க்கு மட்டும்.
  if (!isSingleHomeRefresh) {
    if (_homeBox.isNotEmpty && mounted) {
      setState(() {
        _homes = _homeBox.values.map((h) => h.toMap()).toList();
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

    final response = await http.get(
      Uri.parse(url),
      headers: {'ngrok-skip-browser-warning': 'true'},
    );

    debugPrint('🏠 Home fetch status: ${response.statusCode}');
    debugPrint('🏠 Home fetch body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['data'] != null) {
        final rawData = data['data'];
        final List rawHomes = rawData is List ? rawData : [rawData];

        final parsedHomes = rawHomes.map<Map<String, dynamic>>((h) {
          final roomsRaw = h['rooms'];
          final Map<String, List<Map<String, dynamic>>> rooms = {};
          if (roomsRaw is List) {
            for (final roomObj in roomsRaw) {
              if (roomObj is! Map) continue;
              final roomName = roomObj['roomName']?.toString();
              final devicesRaw = roomObj['devices'];
              if (roomName == null || devicesRaw is! List) continue;

              // Skip the hidden placeholder room created at signup time
              // (see AddressScreen._createHomeRecord) — it only exists to
              // force home creation and should never surface in the UI.
              if (roomName.toLowerCase() == _hiddenSetupRoomKey) continue;

              rooms[roomName.toLowerCase()] =
                  devicesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          } else if (roomsRaw is Map) {
            // Fallback for the older flat-map format, in case any endpoint still sends it.
            roomsRaw.forEach((key, value) {
              if (value is List) {
                // Same skip for the flat-map fallback format.
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
            'members': members,
          };
        }).toList();

        // 👇 NEW: dedupe homes — same address+pincode (or same id) should
        // collapse into ONE home instead of showing duplicates.
        final dedupedHomes = _dedupeHomes(parsedHomes);

        if (isSingleHomeRefresh) {
          if (dedupedHomes.isNotEmpty && mounted) {
            final updated = dedupedHomes.first;
            final idx = _homes.indexWhere((h) => h['id']?.toString() == homeId);
            setState(() {
              if (idx != -1) {
                _homes[idx] = updated;
              } else {
                _homes.add(updated);
              }
              _localExtraRooms.clear();
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

        if (mounted) {
          setState(() {
            _homes = dedupedHomes;
            if (_selectedHomeIndex >= _homes.length) _selectedHomeIndex = 0;
            _localExtraRooms.clear();
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

List<Map<String, dynamic>> _dedupeHomes(List<Map<String, dynamic>> homes) {
    final Map<String, Map<String, dynamic>> merged = {};
    final List<String> order = []; // preserve first-seen order
    for (final home in homes) {
      final id = home['id']?.toString();
      final address = home['address']?.toString() ?? '';
      final pincode = home['pincode']?.toString() ?? '';
      final key = (id != null && id.isNotEmpty)
          ? 'id:$id'
          : 'addr:${address.trim().toLowerCase()}|${pincode.trim()}';
      if (!merged.containsKey(key)) {
        final roomsIn = home['rooms'] as Map<String, List<Map<String, dynamic>>>;
        merged[key] = {
          'id': home['id'],
          'address': home['address'],
          'pincode': home['pincode'],
          'rooms': roomsIn.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v))),
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
        final existingMembers = existing['members'] as List<Map<String, dynamic>>;
        final existingMobiles = existingMembers.map((m) => m['mobile']?.toString()).toSet();
        final incomingMembers = home['members'] as List<Map<String, dynamic>>;
        for (final m in incomingMembers) {
          if (!existingMobiles.contains(m['mobile']?.toString())) {
            existingMembers.add(m);
          }
        }
      }
    }
    return order.map((key) => merged[key]!).toList();
  }


  // ---------------------------------------------------------------------
  // CURRENT HOME HELPERS
  // ---------------------------------------------------------------------
  Map<String, dynamic>? get _currentHome =>
      _homes.isEmpty ? null : _homes[_selectedHomeIndex];

  Map<String, List<Map<String, dynamic>>> get _currentRooms =>
      (_currentHome?['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};

  List<Map<String, dynamic>> get _currentMembers =>
      (_currentHome?['members'] as List<Map<String, dynamic>>?) ?? [];

  String? get _currentHomeId => _currentHome?['id']?.toString();
  String get _currentAddress => _currentHome?['address']?.toString() ?? widget.address;
  String get _currentPincode => _currentHome?['pincode']?.toString() ?? widget.pincode;

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

  // ---------------------------------------------------------------------
  // WARRANTY / STATS / ALERTS
  // (date-parsing logic now lives in WarrantyUtils — no more local copy)
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

  List<Map<String, String>> _computeAlerts() {
    final alerts = <Map<String, String>>[];
    final now = DateTime.now();

    _currentRooms.forEach((roomKey, items) {
      for (final item in items) {
        final product = item['product']?.toString() ?? 'Appliance';
        final brand = item['brand']?.toString() ?? '';
        final label = brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
        final expiry = WarrantyUtils.parseExpiry(
          item['warranty']?.toString(),
          referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
        );

        if (expiry != null) {
          final daysLeft = expiry.difference(now).inDays;
          if (daysLeft < 0) {
            final daysSinceExpiry = -daysLeft;
            alerts.add({
              'type': 'danger',
              'title': 'Warranty expired',
              'subtitle': '$label — expired $daysSinceExpiry day${daysSinceExpiry == 1 ? '' : 's'} ago',
            });
          } else if (daysLeft <= 30) {
            alerts.add({
              'type': 'warning',
              'title': 'Expiring soon',
              'subtitle': '$label warranty — $daysLeft days left',
            });
          }
        }
      }
    });

    return alerts.take(4).toList();
  }

  // ---------------------------------------------------------------------
  // ROOM DETAIL / ADD ROOM
  // ---------------------------------------------------------------------
  void _openRoomDetail(String roomKey, String displayName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RoomDetailScreen(
          roomKey: roomKey,
          roomName: displayName,
          items: _currentRooms[roomKey] ?? [],
          iconForAppliance: _iconForAppliance,
          mobileNumber: widget.mobileNumber,
          address: _currentAddress,
          pincode: _currentPincode,
          name: widget.name,
          homeId: _currentHomeId,
        ),
      ),
    ).then((_) {
      if (_currentHomeId != null) {
        _fetchAppliances(homeId: _currentHomeId);   // 👈 single-home refresh
      } else {
        _fetchAppliances();
      }
    });
  }

  // ---------------------------------------------------------------------
  // ADD A ROOM — 3-step guided flow:
  //   Step 1: pick a room type (icon grid)
  //   Step 2: name the room (pre-filled suggestion + quick-suggestion chips)
  //   Step 3: room added confirmation + quick device suggestions
  // ---------------------------------------------------------------------
  void _openAddRoomDialog() {
    int step = 0;
    Map<String, dynamic>? selectedType;
    final nameController = TextEditingController();
    String createdDisplay = '';
    final Set<String> addedQuickDevices = {};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget dots() {
              return Row(
                children: List.generate(3, (i) {
                  final active = i <= step;
                  return Container(
                    margin: const EdgeInsets.only(right: 5),
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.borderSubtle,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Add a room', style: AppText.dialogTitle),
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        borderRadius: BorderRadius.circular(20),
                        child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text('Choose the room type', style: AppText.faintCaption),
                  const SizedBox(height: 10),
                  dots(),
                  const SizedBox(height: 16),
                  const Text('COMMON ROOMS',
                      style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
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
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: selectedType == null
                          ? null
                          : () {
                              final key = selectedType!['key'] as String;
                              final suggestions = _roomNameSuggestions[key];
                              nameController.text = (key != 'custom' && suggestions != null && suggestions.isNotEmpty)
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
              final homeLabel = _currentAddress.isNotEmpty ? _currentAddress.split(',').first.trim() : 'Home';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Name this room', style: AppText.dialogTitle),
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        borderRadius: BorderRadius.circular(20),
                        child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
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
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                          child: Icon(type['icon'] as IconData, color: color, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type['label'] as String,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                              Text('$homeLabel home', style: AppText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('ROOM NAME',
                      style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  AppDialogField(controller: nameController, hint: 'e.g. Living Hall'),
                  const SizedBox(height: 4),
                  const Text('Give it a name that helps you identify it quickly', style: AppText.faintCaption),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('QUICK SUGGESTIONS',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
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
                              border: Border.all(color: isChosen ? AppColors.primary : AppColors.borderSubtle),
                            ),
                            child: Text(s,
                                style: TextStyle(
                                    color: isChosen ? AppColors.primary : AppColors.textSecondary, fontSize: 12.5)),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter a room name.')),
                          );
                          return;
                        }
                        final roomKey = name.toLowerCase();
                        if (_currentRooms.containsKey(roomKey) || _localExtraRooms.containsKey(roomKey)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('This room already exists.')),
                          );
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
                      child: const Text('← Back', style: TextStyle(color: AppColors.textMuted)),
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
              final homeLabel = _currentAddress.isNotEmpty ? _currentAddress.split(',').first.trim() : 'Home';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Room added', style: AppText.dialogTitle),
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        borderRadius: BorderRadius.circular(20),
                        child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('$homeLabel — ${widget.name.isNotEmpty ? widget.name : "You"}', style: AppText.faintCaption),
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
                            style: const TextStyle(color: AppColors.success, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('$homeLabel home · 0 devices so far', style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text("What's in this room? Add devices now",
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...devices.map((d) {
                        final label = d['label'] as String;
                        final icon = d['icon'] as IconData;
                        final isAdded = addedQuickDevices.contains(label);
                        return InkWell(
                          onTap: () => setDialogState(() {
                            if (isAdded) {
                              addedQuickDevices.remove(label);
                            } else {
                              addedQuickDevices.add(label);
                            }
                          }),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isAdded ? AppColors.primarySoft : AppColors.cardBgAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isAdded ? AppColors.primary : AppColors.borderSubtle),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 14, color: isAdded ? AppColors.primary : AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(label,
                                    style: TextStyle(
                                        color: isAdded ? AppColors.primary : AppColors.textSecondary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        );
                      }),
                      InkWell(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          widget.onScanTap?.call(
                            homeId: _currentHomeId,
                            address: _currentAddress,
                            pincode: _currentPincode,
                            knownRooms: _displayRooms.map((e) => e.value).toList(),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_scanner_rounded, size: 14, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text('Scan any', style: TextStyle(color: AppColors.primary, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        widget.onScanTap?.call(
                          homeId: _currentHomeId,
                          address: _currentAddress,
                          pincode: _currentPincode,
                          knownRooms: _displayRooms.map((e) => e.value).toList(),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppColors.textPrimary),
                      label: const Text('Scan and add first device', style: AppText.button),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Done — go to home', style: TextStyle(color: AppColors.textMuted)),
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
  // ADD HOME (creates a brand-new home record via a fresh address)
  // ---------------------------------------------------------------------
// ---------------------------------------------------------------------
  // ADD HOME — now pushes AddressScreen (isAddingHome: true) instead of a
  // small inline dialog, so the user gets "use current location" too.
  // AddressScreen creates the home + refreshes this list, then pops back.
  // ---------------------------------------------------------------------
void _openAddHomeDialog() async {
  // If a "Default" home already exists (created silently by Skip+Scan),
  // registering now should UPDATE that same home's address instead of
  // creating a brand-new one — otherwise already-scanned devices get
  // orphaned under the old "Default" home.
  final existingDefaultId = _defaultHome?['id']?.toString();

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

  if (existingDefaultId != null) {
    // Promote the existing Default home — reuses _submitAddressUpdate,
    // which already calls the existing EntityUpdateService.update() API
    // (same one _openEditAddressDialog uses), so no backend change needed.
    if (newAddress.isEmpty) return;
    final ok = await _submitAddressUpdate(existingDefaultId, newAddress, newPincode);
    if (ok && mounted) {
      await _fetchAppliances(homeId: existingDefaultId);
      setState(() {
        final idx = _homes.indexWhere((h) => h['id']?.toString() == existingDefaultId);
        if (idx != -1) _selectedHomeIndex = idx;
        _serviceCounts.clear();
      });
      _prefetchServiceCounts();
    }
    return;
  }

  // No default home yet — genuine "add a new home" path, unchanged.
  await _fetchAppliances();
  setState(() {
    _selectedHomeIndex = _homes.length - 1;
    _serviceCounts.clear();
  });
  _prefetchServiceCounts();

  if (newAddress.isNotEmpty) {
    widget.onScanTap?.call(
      homeId: _currentHomeId,
      address: newAddress,
      pincode: newPincode,
    );
  }
}

  // ---------------------------------------------------------------------
  // EDIT HOME ADDRESS
  // ---------------------------------------------------------------------
  void _openEditAddressDialog(int index, Map<String, dynamic> home) {
    final addressController = TextEditingController(text: home['address']?.toString() ?? '');
    final pincodeController = TextEditingController(text: home['pincode']?.toString() ?? '');
    final homeId = home['id']?.toString();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: AppDecor.dialogShape,
              title: const Text('Edit Address', style: AppText.dialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppDialogField(controller: addressController, hint: 'Address'),
                  const SizedBox(height: 10),
                  AppDialogField(
                    controller: pincodeController,
                    hint: 'Pincode',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
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
                          final newAddress = addressController.text.trim();
                          final newPincode = pincodeController.text.trim();

                          if (newAddress.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter the address.')),
                            );
                            return;
                          }
                          if (homeId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot update this home right now.')),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          final ok = await _submitAddressUpdate(homeId, newAddress, newPincode);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (ok && mounted) {
                            _fetchAppliances(homeId: homeId); // Refresh list
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitAddressUpdate(String homeId, String address, String pincode) async {
    final result = await EntityUpdateService.update(
      homeId: homeId,
      address: address,
      pincode: pincode.isNotEmpty ? pincode : null,
    );

    if (!mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['success'] == true
            ? 'Address updated successfully ✅'
            : (result['message']?.toString() ?? 'Failed to update address')),
      ),
    );
    return result['success'] == true;
  }

  // ---------------------------------------------------------------------
  // ADD MEMBER — Contacts-only (no manual name/mobile typing)
  // ---------------------------------------------------------------------
  void _openAddMemberDialog() {
    String? pickedName;
    String? pickedMobile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickFromContacts() async {
              final granted = await FlutterContacts.requestPermission();
              if (!granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contacts permission denied.')),
                );
                return;
              }
              final contact = await FlutterContacts.openExternalPick();
              if (contact == null) return;

              // openExternalPick sometimes returns without full details,
              // so fetch the full contact to be safe.
              final full = await FlutterContacts.getContact(contact.id);
              if (full == null) return;

              String phone = full.phones.isNotEmpty ? full.phones.first.number : '';
              // Keep only digits, then take the last 10 (strips +91 etc.)
              phone = phone.replaceAll(RegExp(r'\D'), '');
              if (phone.length > 10) phone = phone.substring(phone.length - 10);

              if (phone.length != 10) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('This contact has no valid 10-digit number.')),
                  );
                }
                return;
              }

              setDialogState(() {
                pickedName = full.displayName;
                pickedMobile = phone;
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: AppDecor.dialogShape,
              title: const Text('Add Member', style: AppText.dialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'They will be able to see and manage all appliances in this home.',
                    style: AppText.faintCaption,
                  ),
                  const SizedBox(height: 14),

                  // ---- Pick from Contacts button (only way to add) ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: pickFromContacts,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.contacts_rounded, color: AppColors.primary, size: 18),
                      label: const Text('Pick from Contacts', style: TextStyle(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ---- Selected contact preview (read-only) ----
                  if (pickedName != null && pickedMobile != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.memberAvatarBg,
                            child: Icon(Icons.person, color: AppColors.textPrimary, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pickedName!,
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                                Text(pickedMobile!, style: AppText.caption),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => setDialogState(() {
                              pickedName = null;
                              pickedMobile = null;
                            }),
                            child: const Icon(Icons.close, color: AppColors.textFaint, size: 18),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text('No contact selected yet.', style: AppText.faintCaption),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: (isSubmitting || pickedName == null || pickedMobile == null)
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          await _submitAddMember(pickedName!, pickedMobile!);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('Add', style: TextStyle(color: AppColors.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitAddMember(String name, String newMobile) async {
    try {
      final myMobile = ApiConfig.stripCountryCode(widget.mobileNumber);

      if (_currentHomeId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No home selected. Please select a home first.')),
          );
        }
        return;
      }

      final response = await http.post(
        Uri.parse(ApiConfig.memberAddUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'homeId': _currentHomeId,
          'myMobile': myMobile,
          'newName': name,
          'newMobile': newMobile,
        }),
      );

      debugPrint('👥 Add member status: ${response.statusCode}');
      debugPrint('👥 Add member body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Member added successfully ✅')),
        );
        _fetchAppliances();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Could not add member.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Add member error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // DELETE MEMBER
  // ---------------------------------------------------------------------
  Future<void> _submitDeleteMember(String mobile, String name) async {
    if (_currentHomeId == null) return;
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.memberDeleteUrl(_currentHomeId!)),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'mobile': mobile}),
      );

      debugPrint('🗑️ Delete member status: ${response.statusCode}');
      debugPrint('🗑️ Delete member body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name removed ✅')),
        );
        _fetchAppliances();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Could not remove member.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Delete member error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
      }
    }
  }

  Future<void> _confirmDeleteMember(String name, String mobile) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Remove member?',
      content: '$name will lose access to this home.',
    );
    if (ok == true) _submitDeleteMember(mobile, name);
  }

  // ---------------------------------------------------------------------
  // ADD APPLIANCE — "+" BUTTON POPUP (Scan to Add / Add Manually)
  // ---------------------------------------------------------------------
  void _openAddOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Appliance', style: AppText.dialogTitle),
              const SizedBox(height: 4),
              const Text('How do you want to add it?', style: AppText.faintCaption),
              const SizedBox(height: 18),
              _addOptionTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan to Add',
                subtitle: 'Point your camera at the appliance',
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onScanTap?.call(
                    homeId: _currentHomeId,
                    address: _currentAddress,
                    pincode: _currentPincode,
                    knownRooms: _displayRooms.map((e) => e.value).toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
              _addOptionTile(
                icon: Icons.edit_note_rounded,
                title: 'Add',
                subtitle: 'Type in the product details yourself',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openManualAddDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _addOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppDecor.outlinedCard(radius: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.faintCaption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  // Manual entry form — product / brand / warranty / room, no camera needed.
  void _openManualAddDialog() {
    final productController = TextEditingController();
    final brandController = TextEditingController();
    final warrantyController = TextEditingController();
    String selectedRoom = 'Hall';
    bool isCustomRoom = false;
    bool isSubmitting = false;

    // Lets the "Add appliance" button gate itself on the product field
    // without assuming AppDialogField exposes an onChanged callback — we
    // just listen to the controller directly and re-run setDialogState.
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
        widget.onScanTap?.call(
          homeId: _currentHomeId,
          address: _currentAddress,
          pincode: _currentPincode,
          knownRooms: _displayRooms.map((e) => e.value).toList(),
        );
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
                    AppDialogField(controller: warrantyController, hint: 'Warranty (e.g. 2 Years, optional)'),
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
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  // Task-specific CTA: stays disabled until the required
                  // product name is actually filled in, instead of relying
                  // on a snackbar error after the tap.
                  onPressed: (isSubmitting || !productHasText)
                      ? null
                      : () async {
                          final product = productController.text.trim();
                          if (product.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter the product name.')),
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          final ok = await _submitManualAppliance(
                            product: product,
                            brand: brandController.text.trim(),
                            warranty: warrantyController.text.trim(),
                            room: selectedRoom,
                          );
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          if (ok) {
                            if (_currentHomeId != null) {
                              _fetchAppliances(homeId: _currentHomeId);   // 👈
                            } else {
                              _fetchAppliances();
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('Add appliance', style: TextStyle(color: AppColors.textPrimary)),
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
      // Same rule as ScanTab — backend needs a real homeId before it will
      // accept a product submission.
      String? homeIdToUse = _currentHomeId;
      if (homeIdToUse == null) {
        final response = await http.post(
          Uri.parse(ApiConfig.createHomeUrl),
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({
            'name': widget.name,
            'mobile': ApiConfig.stripCountryCode(widget.mobileNumber),
            'address': _currentAddress,
          }),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            homeIdToUse = data['data']['homeId']?.toString();
          }
        }
        if (homeIdToUse == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not set up your home. Try again.')),
            );
          }
          return false;
        }
        await SessionManager.updateHomeId(homeIdToUse);
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.productSubmitUrl),
      );
      request.headers['ngrok-skip-browser-warning'] = 'true';

      request.fields['homeId'] = homeIdToUse;
      request.fields['address'] = _currentAddress;
      request.fields['product'] = product;
      request.fields['brand'] = brand.isNotEmpty ? brand : 'Unknown';
      request.fields['mobile'] = ApiConfig.stripCountryCode(widget.mobileNumber);
      request.fields['pincode'] = _currentPincode;
      request.fields['warranty'] = warranty.isNotEmpty ? warranty : 'N/A';
      request.fields['roomName'] = room;
      request.fields['name'] = widget.name;

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('📦 Manual submit status: ${response.statusCode}');
      debugPrint('📦 Manual submit body: ${response.body}');

      if (!mounted) return false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$product added ✅')),
        );
        return true;
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(data['message']?.toString() ?? 'Could not add appliance. Try again.')));
        return false;
      }
    } catch (e) {
      debugPrint('❌ Manual submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // REFER A FRIEND
  // ---------------------------------------------------------------------
  void _openReferFriendSheet(BuildContext context) {
    const referralMessage =
        "Hey! I've been using ZHINI to track all my home appliances, warranties, and find repair services in one place. Try it out 👉 https://zhini.app/download";

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text('Refer a Friend', style: AppText.dialogTitle),
        content: const Text(
          "Share ZHINI with friends and family — they'll be able to track their own home's appliances too.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: referralMessage));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Referral message copied — paste it anywhere ✅')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textPrimary),
            label: const Text('Copy Link', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // MY HOMES (list + edit) — shown inside the profile sheet
  // ---------------------------------------------------------------------
  Widget _buildMyHomesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MY HOMES',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        const SizedBox(height: 10),
        ..._homes.asMap().entries.map((entry) {
          final index = entry.key;
          final home = entry.value;
          final address = home['address']?.toString() ?? '';
          final pincode = home['pincode']?.toString() ?? '';
          final isSelected = index == _selectedHomeIndex;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBgAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary.withValues(alpha: 0.6) : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address.isNotEmpty ? address.split(',').first : 'Home ${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSelected
                            ? 'Currently viewing${pincode.isNotEmpty ? ' · Pincode $pincode' : ''}'
                            : (pincode.isNotEmpty ? 'Pincode $pincode' : 'AMC · Active'),
                        style: isSelected
                            ? const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)
                            : AppText.faintCaption,
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _openEditAddressDialog(index, home);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_rounded, size: 15, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openAddHomeDialog();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: AppColors.borderMuted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add_home_rounded, color: AppColors.textSecondary, size: 16),
            label: const Text('Add another home', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // PROFILE SHEET
  // ---------------------------------------------------------------------
  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        final myPlain = ApiConfig.stripCountryCode(widget.mobileNumber);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Profile',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            InkWell(
              onTap: () => Navigator.pop(sheetContext),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
                // Top Header - Compact
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'P',
                        style: const TextStyle(fontSize: 20, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name.isNotEmpty ? widget.name : 'Petchirajan',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            widget.mobileNumber,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: AppColors.borderSubtle, thickness: 0.8),
                const SizedBox(height: 12),

                // ---- HOUSEHOLD section (separated from Account below,
                // per "group household management" recommendation) ----
                const Text('HOUSEHOLD',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                const SizedBox(height: 10),

                ..._currentMembers.map((m) {
                  final name = m['name']?.toString() ?? 'Member';
                  final mobile = m['mobile']?.toString() ?? '';
                  final isMe = mobile == myPlain;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 16, backgroundColor: AppColors.memberAvatarBg, child: Icon(Icons.person, color: AppColors.textPrimary, size: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isMe ? '$name (You)' : name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                              Text(isMe ? 'Owner' : 'Member', style: AppText.caption),
                            ],
                          ),
                        ),
                        Text(mobile, style: AppText.caption),
                        if (!isMe) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _confirmDeleteMember(name, mobile),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openAddMemberDialog();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.person_add, color: AppColors.primary, size: 18),
                    label: const Text('Add Member', style: TextStyle(color: AppColors.primary, fontSize: 14)),
                  ),
                ),
                // inside _showProfileSheet, after the "Add Member" OutlinedButton:

                const SizedBox(height: 18),
                const Divider(color: AppColors.borderSubtle),
                const SizedBox(height: 12),

                // MY HOMES - Compact, active home explicitly marked
                const Text('MY HOMES', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),

                ..._homes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final home = entry.value;
                  final address = home['address']?.toString() ?? '';
                  final pincode = home['pincode']?.toString() ?? '';
                  final isSelected = index == _selectedHomeIndex;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBgAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.6) : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: isSelected ? AppColors.primary : AppColors.textFaint,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(address.split(',').first, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                              Text(
                                isSelected ? 'Selected · Pincode $pincode' : 'Pincode $pincode',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openEditAddressDialog(index, home);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.edit, color: AppColors.primary, size: 18),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openAddHomeDialog();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: AppColors.textMuted),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_home_rounded, color: AppColors.textSecondary, size: 18),
                    label: const Text('Add another home', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(color: AppColors.borderSubtle),

                // ---- ACCOUNT section — refer + logout kept apart from
                // Household/Homes, and logout gets clear destructive styling
                // so it doesn't look equivalent to "Refer a Friend". ----
                const SizedBox(height: 12),
                const Text('ACCOUNT',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openReferFriendSheet(context);
                    },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11), side: const BorderSide(color: AppColors.textFaint), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    icon: const Icon(Icons.share_rounded, color: AppColors.textSecondary, size: 18),
                    label: const Text('Refer a Friend', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _handleLogout(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: AppColors.danger, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.logout, color: AppColors.danger, size: 18),
                    label: const Text('Log out', style: TextStyle(color: AppColors.danger, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showConfirmActionDialog(
      context,
      title: 'Log out?',
      content: "You'll need to verify your mobile number when you sign in again.",
      confirmLabel: 'Log out',
    );

    if (confirm != true) return;

    await SessionManager.clearSession();
    await Hive.box<HomeModel>('homes').clear();

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
@override
Widget build(BuildContext context) {
  final stats = _loading ? null : _computeStats();
  final alerts = _loading ? <Map<String, String>>[] : _computeAlerts();
  // No registered home yet (skip-flow) — rooms/stats grid don't apply.
  final hasHome = !_loading && _hasRegisteredHome;
  if (!_loading) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onHomeStatusChanged?.call(hasHome);
    });
  }

  return SafeArea(
    child: Column(
      children: [
        // ================= EVERYTHING SCROLLS TOGETHER =================
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.cardBg,
                  onRefresh: _fetchAppliances,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTopBar(context, stats, alerts, hasHome),
                        const SizedBox(height: 18),

                        // Home switcher only makes sense once a home exists.
                        if (hasHome) ...[
                          _buildHomeSwitcher(),
                          const SizedBox(height: 18),
                        ],

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!, style: AppText.caption),
                          )
                        else if (!hasHome) ...[
                          // ================= NO HOME YET =================
                          _buildRegisterHomeCard(),
                          _buildDefaultHomePreview(),
                          const SizedBox(height: 28),
                          _buildServicesNearYou(),
                        ] else ...[
                          // ================= HAS HOME =================
                          if (alerts.isNotEmpty) ...[
                            _sectionHeader('ACTIVE ALERTS'),
                            const SizedBox(height: 12),
                            ...alerts.map(_buildAlertCard),
                            const SizedBox(height: 4),
                          ],

                          _sectionHeader('MY HOME'),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${stats!['devices']} devices across ${stats['rooms']} rooms',
                              style: AppText.caption,
                            ),
                          ),
                          _buildRoomsGrid(),
                          const SizedBox(height: 12),
                          _addRoomButton(),
                          const SizedBox(height: 20),

                          _buildStatsRow(stats),
                          const SizedBox(height: 20),
                          _buildServicesNearYou(),
                        ],
                      ],
                    ),
                  ),
                ),
        ),

        // ================= FIXED FOOTER (search bar only) =================
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: _buildBottomArea(),
        ),
      ],
    ),
  );
}

  // Shown instead of the rooms/stats sections when the user has no
  // registered home yet (skip-flow). Tapping "Register" opens the same
  // AddressScreen ("Add Home") flow used everywhere else in the app —
  // on success, _fetchAppliances() picks up the new home automatically
  // and this card is replaced by the normal MY HOME / stats view.
  Widget _buildRegisterHomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
      ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.home_rounded, size: 18, color: Colors.white),
              label: const Text(
                'Register',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // Shown below the Register card when a "Default" home already has
  // scanned devices — reassures the user their scans weren't lost, and
  // nudges them to register so the home becomes permanent.
  Widget _buildDefaultHomePreview() {
    final defaultHome = _defaultHome;
    if (defaultHome == null) return const SizedBox.shrink();

    final rooms = (defaultHome['rooms'] as Map<String, List<Map<String, dynamic>>>?) ?? {};
    final allDevices = <Map<String, dynamic>>[];
    rooms.forEach((_, items) => allDevices.addAll(items));

    if (allDevices.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
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
          const Text(
            "These will move into your home once you register.",
            style: AppText.faintCaption,
          ),
          const SizedBox(height: 12),
          ...allDevices.take(5).map((item) {
            final product = item['product']?.toString() ?? 'Appliance';
            final brand = item['brand']?.toString() ?? '';
            final label = brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
            final imageUrl = item['imageUrl']?.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(_iconForAppliance(product), size: 14, color: AppColors.textFaint),
                          )
                        : Icon(_iconForAppliance(product), size: 14, color: AppColors.textFaint),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (allDevices.length > 5)
            Text(
              '+${allDevices.length - 5} more',
              style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  // Section divider/header, e.g. "── ACTIVE ALERTS ──"
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.primary.withValues(alpha: 0.3), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(title, style: AppText.sectionHeader),
        ),
        Expanded(child: Divider(color: AppColors.primary.withValues(alpha: 0.3), thickness: 1)),
      ],
    );
  }

  // Top bar — now shows a "City · N devices · N alerts" subtitle line under
  // the greeting, and the trailing avatar shows the user's initials instead
  // of a generic person icon.
// Replacement for _buildTopBar() in home_tab.dart
Widget _buildTopBar(BuildContext context, Map<String, int>? stats, List<Map<String, String>> alerts, bool hasHome) {
  final trimmedName = widget.name.trim();
  final hasName = trimmedName.isNotEmpty;

  // 👈 No more hardcoded 'P' — falls back to a generic person icon when
  // there's no real name yet.
  final initials = hasName
      ? trimmedName.split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase()
      : null;

  final cityName = _currentAddress.isNotEmpty ? _currentAddress.split(',').first.trim() : '';
  final subtitleParts = <String>[
    if (cityName.isNotEmpty) cityName,
    // 👈 Only show the device count once a real home exists — skip-flow
    // users no longer see "0 devices".
    if (hasHome && stats != null) '${stats['devices']} devices',
    if (alerts.isNotEmpty) '${alerts.length} alert${alerts.length == 1 ? '' : 's'}',
  ];
  final subtitle = subtitleParts.join(' · ');

  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.home_rounded, color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasName ? 'Good day, ${widget.name} 👋' : 'Good day 👋',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      InkWell(
        onTap: widget.onProfileTap ?? () => _showProfileSheet(context),
        borderRadius: BorderRadius.circular(20),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.primary,
          child: initials != null
              ? Text(
                  initials,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                )
              : const Icon(Icons.person_rounded, color: AppColors.textPrimary, size: 16),
        ),
      ),
    ],
  );
}

Widget _buildHomeSwitcher() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _homes.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _homes.length) {
            return InkWell(
              onTap: _openAddHomeDialog,
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.add, size: 20, color: AppColors.primary),
              ),
            );
          }
          final isSelected = index == _selectedHomeIndex;
          return ChoiceChip(
            label: Text(_homeLabel(_homes[index], index)),
            selected: isSelected,
            onSelected: (_) {
              setState(() {
                _selectedHomeIndex = index;
                _serviceCounts.clear();
              });
              _prefetchServiceCounts();
            },
            backgroundColor: AppColors.cardBg,
            selectedColor: AppColors.primary,
            labelStyle: isSelected ? AppText.chipSelected : AppText.chipUnselected,
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.borderMuted),
          );
        },
      ),
    );
  }

  Widget _buildRoomsGrid() {
    final rooms = _displayRooms;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final roomKey = rooms[index].key;
        final displayName = rooms[index].value;
        final items = _currentRooms[roomKey] ?? [];
        final previewItems = items.take(2).toList();
        final extraCount = items.length - previewItems.length;

        return InkWell(
          onTap: () => _openRoomDetail(roomKey, displayName),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: AppDecor.flatCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconForRoom(roomKey), color: AppColors.primary, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${items.length} appliance${items.length == 1 ? '' : 's'}', style: AppText.faintCaption),
                const SizedBox(height: 8),
                // ---- Bullet-list of appliances (matches new design) ----
                Expanded(
                  child: previewItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No appliances yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textDisabled, fontSize: 10.5),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            ...previewItems.map((item) {
                              final product = item['product']?.toString() ?? '';
                              final imageUrl = item['imageUrl']?.toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    if (imageUrl != null && imageUrl.isNotEmpty)
                                      Container(
                                        width: 16,
                                        height: 16,
                                        margin: const EdgeInsets.only(right: 5),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: AppColors.borderSubtle,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(
                                              Icons.image_not_supported_rounded,
                                              size: 10, color: AppColors.textDisabled),
                                        ),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Text('•', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                      ),
                                    Expanded(
                                      child: Text(
                                        product,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (extraCount > 0)
                              Text(
                                '+$extraCount more',
                                style: const TextStyle(
                                    color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // "Add New Room" — full-width outlined button below the rooms grid
  // (previously a card inside the grid itself).
  Widget _addRoomButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openAddRoomDialog,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 18),
        label: const Text('Add New Room',
            style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // Stats row — "Attention" (actionable) leads and gets a bolder/emphasized
  // treatment when > 0, instead of giving all four counters equal weight.
  Widget _buildStatsRow(Map<String, int> stats) {
    Widget statBox(String value, String label, Color color, {bool emphasized = false}) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(vertical: emphasized ? 14 : 10),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: emphasized ? color.withValues(alpha: 0.1) : AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: emphasized ? 0.6 : 0.25), width: emphasized ? 1.4 : 1),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: emphasized ? 20 : 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: emphasized ? color : AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final needsAttention = stats['attention']! > 0;

    return Row(
      children: [
        statBox('${stats['attention']}', 'Attention', AppColors.warning, emphasized: needsAttention),
        statBox('${stats['warranty']}', 'Warranty OK', AppColors.success),
        statBox('${stats['devices']}', 'Devices', AppColors.textMuted),
        statBox('${stats['rooms']}', 'Rooms', AppColors.textMuted),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, String> alert) {
    final isDanger = alert['type'] == 'danger';
    final color = AppColors.statusColor(alert['type'] ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDanger ? Icons.error_outline_rounded : Icons.access_time_rounded, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert['title'] ?? '',
                        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(alert['subtitle'] ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          // ---- "Book Local Repair" action (matches new design) ----
          if (isDanger) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening repair booking…')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Book Local Repair', style: TextStyle(color: color, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Wraps the search bar + separate "+" button row.
  Widget _buildBottomArea() {
    return _buildAskZhiniRow();
  }

  // The "Ask ZHINI" pill search bar, with the "+" add button sitting
  // OUTSIDE it as its own circular button on the right. The "+" now opens
  // the same labeled action sheet as everywhere else (Scan / Add Appliance)
  // instead of jumping straight into the manual-entry dialog, so there is
  // one consistent Add flow across the app.
Widget _buildAskZhiniRow() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
      ],
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Ask ZHINI anything about your home…',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        const Icon(Icons.mic_none_rounded, color: AppColors.textMuted, size: 20),
      ],
    ),
  );
}
}

class _RoomDetailScreen extends StatefulWidget {
  final String roomKey;
  final String roomName;
  final List<Map<String, dynamic>> items;
  final IconData Function(String) iconForAppliance;
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final String? homeId;

  const _RoomDetailScreen({
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
  State<_RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<_RoomDetailScreen> {
  late List<Map<String, dynamic>> _items;
  bool _deleting = false;

  // serviceKey ("brand|product|tier") -> fetched provider list, cached so
  // re-opening the same appliance's booking sheet doesn't re-hit the API.
  final Map<String, List<Map<String, dynamic>>> _serviceCache = {};

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
  }

  // Opens the given image URL full-screen, pinch-to-zoom enabled.
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
                errorBuilder: (_, _, _) => const Padding(
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

  Future<void> _submitDeleteProduct(String product) async {
    if (widget.homeId == null || _deleting) return;
    setState(() => _deleting = true);
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.productDeleteUrl(widget.homeId!)),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'roomName': widget.roomKey,
          'product': product,
        }),
      );

      debugPrint('🗑️ Delete product status: ${response.statusCode}');
      debugPrint('🗑️ Delete product body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _items.removeWhere((item) => item['product']?.toString() == product);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$product removed ✅')),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Could not remove appliance.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Delete product error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
      }
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

  void _openEditDeviceDialog(Map<String, dynamic> item) {
    final deviceId = (item['deviceId'] ?? item['_id'])?.toString();
    if (deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('இந்த item-க்கு deviceId இல்ல, edit முடியாது.')),
      );
      return;
    }

    final productController = TextEditingController(text: item['product']?.toString() ?? '');
    final brandController = TextEditingController(text: item['brand']?.toString() ?? '');
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
                        homeId: widget.homeId,
                        deviceId: deviceId,
                        product: productController.text.trim().isNotEmpty
                            ? productController.text.trim()
                            : null,
                        brand: brandController.text.trim().isNotEmpty
                            ? brandController.text.trim()
                            : null,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result['success'] == true
                            ? 'Appliance updated ✅'
                            : (result['message']?.toString() ?? 'Update failed'))),
                      );
                      if (result['success'] == true) {
                        setState(() {
                          item['product'] = productController.text.trim();
                          item['brand'] = brandController.text.trim();
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

  // ---------------------------------------------------------------------
  // BOOK SERVICE PROVIDER — appears on every appliance card. The button's
  // color/label/tier follow the appliance's warranty status:
  //   under warranty  -> green "Book authorized service" -> Tier 1
  //   expired/unknown -> red   "Find repair near me"      -> Tier 2/3
  // Hits the SAME /getNearbyService endpoint the "Services near you"
  // section on HomeTab uses, so the backend logic is fully reused.
  // ---------------------------------------------------------------------
  bool _isItemUnderWarranty(Map<String, dynamic> item) {
    final expiry = WarrantyUtils.parseExpiry(
      item['warranty']?.toString(),
      referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
    );
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  // Short, human pill text for the card badge — "8 months left",
  // "Expired 12 days ago", or a neutral fallback when no date parses.
  String _warrantyStatusText(Map<String, dynamic> item) {
    final expiry = WarrantyUtils.parseExpiry(
      item['warranty']?.toString(),
      referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
    );
    if (expiry == null) return 'Warranty status unknown';

    final daysDiff = expiry.difference(DateTime.now()).inDays;
    if (daysDiff < 0) {
      final days = -daysDiff;
      return 'Expired $days day${days == 1 ? '' : 's'} ago';
    }
    if (daysDiff >= 60) {
      final months = (daysDiff / 30).round();
      return '$months month${months == 1 ? '' : 's'} left';
    }
    return '$daysDiff day${daysDiff == 1 ? '' : 's'} left';
  }
  Future<List<Map<String, dynamic>>> _fetchNearbyProviders(
    Map<String, dynamic> item,
    bool isUnderWarranty,
  ) async {
    final brand = item['brand']?.toString() ?? '';
    final product = item['product']?.toString() ?? '';
    final cacheKey = '$brand|$product|$isUnderWarranty'.toLowerCase();
    if (_serviceCache.containsKey(cacheKey)) return _serviceCache[cacheKey]!;

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.nearbyServiceUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'brand': brand,
          'product': product,
          'pincode': widget.pincode,
          'isUnderWarranty': isUnderWarranty,
        }),
      );

      debugPrint('🛠️ Nearby service status: ${response.statusCode}');
      debugPrint('🛠️ Nearby service body: ${response.body}');

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

// Nearby-services fetch — always uses live GPS lat/long. No pincode
  // fallback anymore; "Services near you" is current-location-only.

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('Call launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not start call.')));
      }
    }
  }

  Future<void> _openMapDirections(String address) async {
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Directions launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open maps.')));
      }
    }
  }

  // ---------------------------------------------------------------------
  // CREATE SERVICE TICKET — hits POST /createServiceTicket. Required
  // fields on the backend: customerName, cust_number, address,
  // providerMobile. description + availableTime are optional context.
  // ---------------------------------------------------------------------
  Future<bool> _submitServiceTicket({
    required Map<String, dynamic> provider,
    required Map<String, dynamic> item,
    required bool isUnderWarranty,
    String? availableTime,
  }) async {
    final providerMobile = (provider['mobile'] ?? provider['phone'])?.toString();
    if (providerMobile == null || providerMobile.isEmpty || providerMobile == 'N/A') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This provider has no contact number on file.')),
        );
      }
      return false;
    }

    final product = item['product']?.toString() ?? 'Appliance';
    final brand = item['brand']?.toString() ?? '';
    final label = brand.isNotEmpty && brand.toUpperCase() != 'N/A' ? '$brand $product' : product;
    final warrantyNote = isUnderWarranty ? 'Under warranty' : 'Out of warranty';

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.createServiceTicketUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'customerName': widget.name.isNotEmpty ? widget.name : 'Customer',
          'cust_number': ApiConfig.stripCountryCode(widget.mobileNumber),
          'address': widget.address,
          'description': '$label — $warrantyNote. Room: ${widget.roomName}.',
          'providerMobile': providerMobile,
          if (availableTime != null && availableTime.trim().isNotEmpty) 'availableTime': availableTime.trim(),
        }),
      );

      debugPrint('🎫 Create ticket status: ${response.statusCode}');
      debugPrint('🎫 Create ticket body: ${response.body}');

      if (!mounted) return false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service booked ✅ — the provider will reach out shortly.')),
        );
        return true;
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Could not book this provider.')),
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ Create ticket error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
      }
      return false;
    }
  }

  // Small confirm dialog — lets the customer optionally note a preferred
  // time slot before the ticket is created against the chosen provider.
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
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
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
                          if (ok && mounted) Navigator.pop(context); // close the provider sheet too
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('Book', style: TextStyle(color: AppColors.textPrimary)),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchNearbyProviders(item, isUnderWarranty),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (providers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No service providers found nearby.',
                        style: AppText.faintCaption,
                      ),
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
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ServiceProviderCard(
                                name: p['name']?.toString() ?? 'Not available',
                                address: address,
                                phone: phone,
                                rating: rating,
                                onCall: (phone != null && phone.isNotEmpty && phone != 'N/A')
                                    ? () => _callNumber(phone)
                                    : null,
                                onDirections: (address != null &&
                                        address.isNotEmpty &&
                                        address != 'Address not available')
                                    ? () => _openMapDirections(address)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: (phone != null && phone.isNotEmpty && phone != 'N/A')
                                      ? () => _openBookingDialog(p, item, isUnderWarranty)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.calendar_month_rounded, size: 15, color: Colors.white),
                                  label: const Text('Book this provider',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                ),
                              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(widget.roomName, style: const TextStyle(color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
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
        // Standard extended FAB with an accessible text label, instead of
        // a small custom icon+caption stack.
        icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.textPrimary, size: 20),
        label: const Text('Add appliance', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text('No appliances in this room yet.\nScan one and pick this room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _items[index];
                final product = item['product']?.toString() ?? 'Unknown';
                final brand = item['brand']?.toString() ?? 'N/A';
                final warranty = item['warranty']?.toString() ?? 'N/A';
                final photoUrl = item['imageUrl']?.toString();
                final warrantyCardUrl = item['warrantyCardUrl']?.toString();

                final isUnderWarranty = _isItemUnderWarranty(item);
                final accent = isUnderWarranty ? AppColors.success : AppColors.danger;
                final statusText = _warrantyStatusText(item);
                final statusIcon = isUnderWarranty ? Icons.verified_rounded : Icons.error_rounded;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ---- Thumbnail with a small status badge
                                // pinned to its corner, like a notification dot.
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    GestureDetector(
                                      onTap: (photoUrl != null && photoUrl.isNotEmpty)
                                          ? () => _openImagePreview(context, photoUrl)
                                          : null,
                                      child: Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: (photoUrl != null && photoUrl.isNotEmpty)
                                            ? Image.network(
                                                photoUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Icon(
                                                    widget.iconForAppliance(product), color: accent, size: 26),
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
                                        child: Icon(statusIcon, size: 11, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                // ---- Tappable body opens the card's
                                // details/overflow rather than exposing
                                // three tiny icon buttons up front. ----
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
                                                  style: const TextStyle(
                                                      color: AppColors.textPrimary,
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600)),
                                            ),
                                            // Single overflow menu replaces the
                                            // three separate tiny icon buttons.
                                            PopupMenuButton<String>(
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(Icons.more_vert_rounded,
                                                  color: AppColors.textMuted, size: 18),
                                              color: AppColors.cardBg,
                                              onSelected: (value) {
                                                if (value == 'edit') _openEditDeviceDialog(item);
                                                if (value == 'service') _openServiceBookingSheet(item);
                                                if (value == 'delete') {
                                                  if (!_deleting) _confirmDeleteProduct(product);
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(children: [
                                                    Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                                    SizedBox(width: 8),
                                                    Text('Edit', style: TextStyle(color: AppColors.textPrimary)),
                                                  ]),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'service',
                                                  child: Row(children: [
                                                    Icon(Icons.build_rounded, size: 16, color: AppColors.primary),
                                                    SizedBox(width: 8),
                                                    Text('Find service', style: TextStyle(color: AppColors.textPrimary)),
                                                  ]),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(children: [
                                                    Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                                                    SizedBox(width: 8),
                                                    Text('Remove', style: TextStyle(color: AppColors.danger)),
                                                  ]),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(brand, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                        const SizedBox(height: 8),
                                        // ---- Warranty status pill ----
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: accent.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isUnderWarranty
                                                        ? Icons.shield_outlined
                                                        : Icons.access_time_filled_rounded,
                                                    size: 12,
                                                    color: accent,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    statusText,
                                                    style: TextStyle(
                                                        color: accent, fontSize: 11, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
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
                                                    errorBuilder: (_, _, _) => const Icon(Icons.receipt_long,
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
                            // ---- Book Service Provider — solid for danger,
                            // outlined for a healthy warranty ----
                            SizedBox(
                              width: double.infinity,
                              child: isUnderWarranty
                                  ? OutlinedButton.icon(
                                      onPressed: () => _openServiceBookingSheet(item),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: accent.withValues(alpha: 0.5)),
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: Icon(Icons.shield_outlined, size: 15, color: accent),
                                      label: Text('Book authorized service',
                                          style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: () => _openServiceBookingSheet(item),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accent,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.build_rounded, size: 15, color: Colors.white),
                                      label: const Text('Find repair near me',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      // ---- Left accent strip — the signature touch that
                      // makes warranty status readable at a glance. ----
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 4, color: accent),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
class _ServiceCategorySheet extends StatefulWidget {
  final String label;
  final Future<List<Map<String, dynamic>>> Function() fetchServices;

  const _ServiceCategorySheet({
    required this.label,
    required this.fetchServices,
  });

  @override
  State<_ServiceCategorySheet> createState() => _ServiceCategorySheetState();
}

class _ServiceCategorySheetState extends State<_ServiceCategorySheet> {
  static const int _pageSize = 5;
  static const int _maxResults = 20;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });

    final results = await widget.fetchServices();

    if (!mounted) return;
    setState(() {
      _services = results.take(_maxResults).toList();
      _loading = false;
      if (_services.isEmpty) {
        _error = 'Could not find services near your current location.';
      }
    });
  }

  int get _totalPages => (_services.length / _pageSize).ceil().clamp(1, (_maxResults / _pageSize).ceil());

  List<Map<String, dynamic>> get _pageItems {
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, _services.length);
    return start < end ? _services.sublist(start, end) : [];
  }

  Future<void> _callNumber(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (e) {
      debugPrint('Call launch error: $e');
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header: title + top-right X close button ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.label, style: AppText.dialogTitle)),
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Near your current location', style: AppText.faintCaption),
          const SizedBox(height: 16),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(_error!, style: AppText.faintCaption),
            )
          else ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _pageItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = _pageItems[i];
                  final phone = s['phone']?.toString();
                  final address = s['address']?.toString();
                  final ratingRaw = s['rating'];
                  final rating = ratingRaw != null && ratingRaw.toString() != 'N/A'
                      ? double.tryParse(ratingRaw.toString())
                      : null;
                  return ServiceProviderCard(
                    name: s['name']?.toString() ?? 'Not available',
                    address: address,
                    phone: phone,
                    rating: rating,
                    onCall: (phone != null && phone.isNotEmpty && phone != 'N/A')
                        ? () => _callNumber(phone)
                        : null,
                    onDirections: (address != null &&
                            address.isNotEmpty &&
                            address != 'Address not available')
                        ? () => _openMapDirections(address)
                        : null,
                  );
                },
              ),
            ),
            if (_services.length > _pageSize) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Previous'),
                  ),
                  Text('Page ${_page + 1} of $_totalPages', style: AppText.caption),
                  TextButton.icon(
                    onPressed: _page < _totalPages - 1 ? () => setState(() => _page++) : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}