// lib/main_shell.dart
import 'package:flutter/material.dart';
import 'home_tab.dart';
import 'devices_tab.dart';
import 'service_tab.dart';
import 'profile_tab.dart';
import 'scan_tab.dart';
import 'theme/app_theme.dart';

class MainShell extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final String? homeId;

  const MainShell({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.homeId,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _Slot {
  static const home = 0;
  static const scan = 1;
  static const devices = 2;
  static const service = 3;
  static const profile = 4;
}

class _MainShellState extends State<MainShell> {
  final _homeTabKey = GlobalKey<HomeTabState>();
  late String _name = widget.name;
  int _currentIndex = _Slot.home;

  bool _hasHome = false;

  // Values used when ScanTab is opened.
  String? _scanHomeId;
  String _scanAddress = '';
  String _scanPincode = '';
  List<String>? _scanKnownRooms;

  // The home currently SELECTED inside HomeTab (kept in sync via
  // onSelectedHomeChanged). Used by the bottom-nav Scan button.
  String? _selectedHomeId;
  String _selectedAddress = '';
  String _selectedPincode = '';

  @override
  void initState() {
    super.initState();
    _scanHomeId = widget.homeId;
    _scanAddress = widget.address;
    _scanPincode = widget.pincode;
    _scanKnownRooms = null;

    _selectedHomeId = widget.homeId;
    _selectedAddress = widget.address;
    _selectedPincode = widget.pincode;

    _hasHome = false;
  }

  void _switchTab(int index) {
    if (!_hasHome && (index == _Slot.devices || index == _Slot.service)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your home first.')),
      );
      return;
    }
    final switchingToHome = index == _Slot.home;
    setState(() => _currentIndex = index);

    if (switchingToHome) {
      _homeTabKey.currentState?.refresh();
    }
  }

  void _onHomeStatusChanged(bool hasHome) {
    if (hasHome == _hasHome) return;
    setState(() {
      _hasHome = hasHome;
      if (!hasHome && (_currentIndex == _Slot.devices || _currentIndex == _Slot.service)) {
        _currentIndex = _Slot.home;
      }
    });
  }

  // HomeTab tells us which home is selected. No setState needed — we only
  // read these values when the Scan button is tapped.
  void _onSelectedHomeChanged(String? homeId, String address, String pincode) {
    _selectedHomeId = homeId;
    _selectedAddress = address;
    _selectedPincode = pincode;
  }

  void _goToScan({
    String? homeId,
    required String address,
    required String pincode,
    List<String>? knownRooms,
  }) {
    debugPrint('📷 _goToScan homeId=$homeId address=$address pincode=$pincode');
    setState(() {
      _scanHomeId = homeId;
      _scanAddress = address;
      _scanPincode = pincode;
      _scanKnownRooms = knownRooms;
      _currentIndex = _Slot.scan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final homeTab = HomeTab(
      key: _homeTabKey,
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: _name,
      onScanTap: _goToScan,
      onProfileTap: () => _switchTab(_Slot.profile),
      onHomeStatusChanged: _onHomeStatusChanged,
      onSelectedHomeChanged: _onSelectedHomeChanged,
    );

    final devicesTab = DevicesTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: _name,
      onScanTap: _goToScan,
    );

    final serviceTab = ServiceTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: _name,
    );

    final profileTab = ProfileTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: _name,
      onScanTap: _goToScan,
      onNameChanged: (newName) => setState(() => _name = newName),
    );

    final scanSlot = _currentIndex == _Slot.scan
        ? ScanTab(
            key: ValueKey('scan_${_scanHomeId}_$_scanAddress'),
            mobileNumber: widget.mobileNumber,
            address: _scanAddress,
            pincode: _scanPincode,
            name: _name,
            homeId: _scanHomeId,
            onBack: () => _switchTab(_Slot.home),
            onHomeCreated: (newId) {
              setState(() => _scanHomeId = newId);
            },
            initialRoom: null,
            lockRoom: false,
            knownRooms: _scanKnownRooms,
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          homeTab,
          scanSlot,
          devicesTab,
          serviceTab,
          profileTab,
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    final items = <Widget>[
      _navItem(icon: Icons.home_rounded, label: 'Home', slot: _Slot.home),
      if (_hasHome)
        _navItem(icon: Icons.devices_other_rounded, label: 'Devices', slot: _Slot.devices),
      _scanButton(),
      if (_hasHome)
        _navItem(icon: Icons.build_rounded, label: 'Service', slot: _Slot.service),
      _navItem(icon: Icons.person_rounded, label: 'Profile', slot: _Slot.profile),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(top: BorderSide(color: AppColors.borderSubtle, width: 1)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items,
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required int slot,
  }) {
    final selected = _currentIndex == slot;
    final color = selected ? AppColors.primary : AppColors.textMuted;

    return InkWell(
      onTap: () => _switchTab(slot),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Center Scan button — uses the home SELECTED in HomeTab (not the
  // login-time widget.homeId).
  Widget _scanButton() {
    final selected = _currentIndex == _Slot.scan;
    return InkWell(
      onTap: () => _goToScan(
        homeId: _selectedHomeId ?? widget.homeId,
        address: _selectedAddress.isNotEmpty ? _selectedAddress : widget.address,
        pincode: _selectedPincode.isNotEmpty ? _selectedPincode : widget.pincode,
      ),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 46,
        height: 46,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}