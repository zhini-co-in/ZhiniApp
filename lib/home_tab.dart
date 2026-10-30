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
import 'utils/devices_filter_bus.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/device_details_sheet.dart';
import 'widgets/light_card.dart';
import 'widgets/section_header.dart';

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
  final ScanRequest? onScanTap;
  final VoidCallback? onProfileTap;
  final ValueChanged<bool>? onHomeStatusChanged;
  final void Function(String? homeId, String address, String pincode)? onSelectedHomeChanged;
  final ValueChanged<String>? onOpenDevices; // 'All' | 'Warranty' | 'Attention'

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
    this.onOpenDevices,
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
  // NOTE: the backend still groups devices by room. The app no longer shows
  // rooms: every device goes into the "Default" room and the UI flattens all
  // rooms into one device list.
  List<Map<String, dynamic>> _homes = [];
  int _selectedHomeIndex = 0;

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
  // Categories / fetch / sheet all live in HomeServices (shared with Service tab).
  final Map<String, int> _serviceCounts = {};

  // ── Banner carousel ──
  final PageController _bannerController = PageController(viewportFraction: 0.92);
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  static const List<String> _bannerImages = [
    'assets/images/banner_ac.png',
    'assets/images/banner_appliance.png',
    'assets/images/banner_fridge.png',
  ];

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % _bannerImages.length;
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
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchAppliances();
    _prefetchServiceCounts();
    _startBannerTimer();
  }

  // Called by MainShell when the Home tab is tapped.
  Future<void> refresh() async {
    while (_fetchInFlight) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _fetchAppliances();
    if (!mounted) return;
    setState(() => _serviceCounts.clear());
    _prefetchServiceCounts();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------
  // SERVICES NEAR YOU — data (shared HomeServices, pincode only)
  // ---------------------------------------------------------------------
  void _prefetchServiceCounts() {
    HomeServices.prefetchCounts(_currentPincode, (type, count) {
      if (mounted) setState(() => _serviceCounts[type] = count);
    });
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

  void _notifySelectedHome() {
    widget.onSelectedHomeChanged?.call(_currentHomeId, _currentAddress, _currentPincode);
  }

  String _homeLabel(Map<String, dynamic> home, int index) {
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
      homeName: firstPart.isNotEmpty ? firstPart : AppStrings.homeN(_homes.length + 1),
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
      _selectedHomeIndex = idx != -1 ? idx : _homes.length - 1;
      _serviceCounts.clear();
    });
    await SessionManager.updateHomeId(newHomeId);
    _notifySelectedHome();
    _prefetchServiceCounts();
    _snack(AppStrings.homeAdded);
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
        ? AppStrings.addressUpdated
        : (result['message']?.toString() ?? AppStrings.addressUpdateFailed));
    return result['success'] == true;
  }

  // ---------------------------------------------------------------------
  // MANUAL ADD — product / brand / warranty. No room: always "Default".
  // ---------------------------------------------------------------------
  void _openManualAddDialog() {
    final productController = TextEditingController();
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
                          SizedBox(width: 4),
                          Text(AppStrings.scan, style: AppText.linkAction),
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
            ? Center(child: CircularProgressIndicator(color: AppColors.lightPrimary))
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
                              child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                            )
                          else if (!hasHome) ...[
                            _buildRegisterHomeCard(),
                            _buildDefaultHomePreview(),
                            const SizedBox(height: 28),
                            _buildServicesNearYou(),
                          ] else ...[
                            _buildBuildingsHeader(),
                            const SizedBox(height: 16),
                            _buildStatsRow(stats!),
                            const SizedBox(height: 24),
                            SectionHeader(
                              AppStrings.devicesCount(stats['devices']!),
                              actionLabel:
                                  stats['devices']! > _maxDevicesOnHome ? AppStrings.viewAll : null,
                              onManage: stats['devices']! > _maxDevicesOnHome
                                  ? () => _openDevicesTabWith('All')
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _buildDevicesList(),
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

  Widget _buildHeader() {
    final hasName = _displayName.isNotEmpty && _displayName.toLowerCase() != 'guest';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: AppDecor.lightHeaderGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + search + avatar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Text(
                  'ZHINI',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 42,
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
                    child: TextField(
                      style: TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: AppStrings.searchHere,
                        hintStyle: TextStyle(color: AppColors.lightHint, fontSize: 12),
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.lightHint, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.lightSurface,
                    child: Text(
                      hasName ? _displayName[0].toUpperCase() : 'P',
                      style: TextStyle(
                        color: AppColors.lightPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Banner carousel (images are 1600x533 => 3:1)
          AspectRatio(
            aspectRatio: 3 / 1.05,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: _bannerImages.length,
              onPageChanged: (i) {
                setState(() => _bannerIndex = i);
                _startBannerTimer(); // restart the 4 sec count after a swipe
              },
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      _bannerImages[i],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppColors.lightSurface),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < _bannerImages.length; i++)
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
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  // ── Buildings title + dropdown to choose the building ──
  Widget _buildBuildingsHeader() {
    final current = _currentHome;
    final label = current == null ? AppStrings.select : _homeLabel(current, _selectedHomeIndex);

    return Row(
      children: [
        const Text(AppStrings.buildings, style: AppText.lightSectionTitle),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<int>(
              offset: const Offset(0, 48),
              color: AppColors.cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (value) {
                if (value == -1) {
                  _openAddHomeDialog();
                  return;
                }
                if (value == _selectedHomeIndex) return;
                setState(() {
                  _selectedHomeIndex = value;
                  _serviceCounts.clear();
                });
                _notifySelectedHome();
                _prefetchServiceCounts();
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
                                  Text(
                                    _homeLabel(_homes[i], i),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.lightCardTitle,
                                  ),
                                  Text(
                                    _homes[i]['address']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.lightCaption,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const PopupMenuDivider(),
                PopupMenuItem<int>(
                  value: -1,
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 18, color: AppColors.lightPrimary),
                      SizedBox(width: 10),
                      Text(AppStrings.addNewBuilding, style: AppText.lightLink),
                    ],
                  ),
                ),
              ],
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.lightPrimary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.apartment_rounded, size: 18, color: AppColors.lightPrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.lightPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.lightPrimary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Stats ──
  Widget _buildStatsRow(Map<String, int> stats) {
    return Row(
      children: [
        _statCard(Icons.devices_other_rounded, AppColors.lightPrimary, '${stats['devices']}',
            AppStrings.statAppliances,
            onTap: () => _openDevicesTabWith('All')),
        const SizedBox(width: 10),
        _statCard(Icons.verified_user_outlined, AppColors.lightSuccess, '${stats['active']}',
            AppStrings.statActiveWarranties,
            onTap: () => _openDevicesTabWith('Warranty')),
        const SizedBox(width: 10),
        _statCard(Icons.warning_amber_rounded, AppColors.lightWarning, '${stats['attention']}',
            AppStrings.statAttention,
            highlight: (stats['attention'] ?? 0) > 0,
            onTap: () => _openDevicesTabWith('Attention')),
      ],
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label,
      {bool highlight = false, VoidCallback? onTap}) {
    return Expanded(
      child: LightCard(
        onTap: onTap,
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
              style: TextStyle(
                color: AppColors.lightTextDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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

  // ── Devices list (flat, first few) ──
  Widget _buildDevicesList() {
    final devices = _allDeviceEntries;

    if (devices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppDecor.lightCard(),
        child: Column(
          children: [
            Icon(Icons.devices_other_rounded, color: AppColors.lightChevron, size: 32),
            const SizedBox(height: 8),
            const Text(AppStrings.noAppliancesYet, style: AppText.lightCardTitle),
            const SizedBox(height: 4),
            const Text(AppStrings.tapAddDeviceBelow, style: AppText.lightCaption),
          ],
        ),
      );
    }

    final shown = devices.take(_maxDevicesOnHome).toList();

    return Container(
      decoration: AppDecor.lightCard(),
      child: Column(
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            _deviceRow(shown[i]),
            if (i != shown.length - 1)
              Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.lightBorder),
          ],
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
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
                  const SizedBox(height: 2),
                  Text(hasBrand ? brand : AppStrings.brandNotAdded,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.lightCaption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DeviceWarrantyIndicator(e),
          ],
        ),
      ),
    );
  }

  Widget _buildAddApplianceButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openManualAddDialog,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.lightPrimary, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.lightPrimary, size: 18),
        label: const Text(AppStrings.addApplianceManually, style: AppText.lightLink),
      ),
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
            const gap = 10.0;
            const visible = 3; // how many cards visible on screen
            final cardWidth = (constraints.maxWidth - gap * (visible - 1)) / visible;

            return SizedBox(
              height: 118,
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
                    onTap: () => HomeServices.openSheet(context, cat, _currentPincode),
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
                          child: Icon(cat['icon'] as IconData, color: color, size: 22),
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
          Icon(Icons.chevron_right_rounded, color: AppColors.lightChevron, size: 18),
        ],
      ),
    );
  }

  // ── Shown instead of devices/stats when user has no registered home (skip-flow) ──
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
            child: Icon(Icons.add_home_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            AppStrings.setUpYourHome,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.setUpYourHomeDesc,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openAddHomeDialog,
              style: AppDecor.primaryButton,
              icon: Icon(Icons.home_rounded, size: 18, color: AppColors.onPrimary),
              label: Text(
                AppStrings.register,
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