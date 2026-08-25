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

// Internal slot indices used by IndexedStack (NOT the same order as the
// visible bottom-nav buttons — Scan sits visually in the middle but is
// slot 1 here since it needs the extra _scanXxx state below).
class _Slot {
  static const home = 0;
  static const scan = 1;
  static const devices = 2;
  static const service = 3;
  static const profile = 4;
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = _Slot.home;

  // Whether the user currently has at least one registered home. Starts
  // as an optimistic guess based on widget.homeId and gets corrected by
  // HomeTab via onHomeStatusChanged once it finishes its own fetch.
  bool _hasHome = false;

  String? _scanHomeId;
  String _scanAddress = '';
  String _scanPincode = '';
  List<String>? _scanKnownRooms;

  @override
  void initState() {
    super.initState();
    _scanHomeId = widget.homeId;
    _scanAddress = widget.address;
    _scanPincode = widget.pincode;
    _scanKnownRooms = null;
    // Always start gated. widget.homeId can be non-null even in the
    // skip-flow (backend creates a home record with just the hidden
    // __setup__ room), so it isn't reliable proof of a REAL home.
    // HomeTab.onHomeStatusChanged corrects this within one frame.
    _hasHome = false;
  }

  // Devices / Service tabs are gated behind having a registered home —
  // tapping them before that just shows a snackbar instead of switching.
  void _switchTab(int index) {
    if (!_hasHome && (index == _Slot.devices || index == _Slot.service)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your home first.')),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  // Called by HomeTab whenever its own "does the user have a home yet"
  // status changes (after its fetch completes, after a home is
  // added/removed, etc).
  void _onHomeStatusChanged(bool hasHome) {
    if (hasHome == _hasHome) return;
    setState(() {
      _hasHome = hasHome;
      // If home got removed/never existed and user is sitting on a
      // gated tab, bounce them back to Home.
      if (!hasHome && (_currentIndex == _Slot.devices || _currentIndex == _Slot.service)) {
        _currentIndex = _Slot.home;
      }
    });
  }

  // Shared by every tab's "+" / "Scan" buttons (Home, Devices, Profile all
  // take an onScanTap of this exact shape).
  void _goToScan({
    String? homeId,
    required String address,
    required String pincode,
    List<String>? knownRooms,
  }) {
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
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: widget.name,
      onScanTap: _goToScan,
      onProfileTap: () => _switchTab(_Slot.profile),
      onHomeStatusChanged: _onHomeStatusChanged,
    );

    final devicesTab = DevicesTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: widget.name,
      onScanTap: _goToScan,
    );

    final serviceTab = ServiceTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: widget.name,
    );

    final profileTab = ProfileTab(
      mobileNumber: widget.mobileNumber,
      address: widget.address,
      pincode: widget.pincode,
      name: widget.name,
      onScanTap: _goToScan,
    );

    // Only build ScanTab when it's actually the visible slot — same as
    // your original SizedBox.shrink() placeholder pattern, so ScanTab's
    // camera doesn't stay initialized in the background on other tabs.
    final scanSlot = _currentIndex == _Slot.scan
        ? ScanTab(
            mobileNumber: widget.mobileNumber,
            address: _scanAddress,
            pincode: _scanPincode,
            name: widget.name,
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
          homeTab,       // _Slot.home    = 0
          scanSlot,      // _Slot.scan    = 1
          devicesTab,    // _Slot.devices = 2
          serviceTab,    // _Slot.service = 3
          profileTab,    // _Slot.profile = 4
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    // Devices/Service are fully hidden (not just dimmed) until the user
    // has a registered home — skip-flow users only see Home/Profile +
    // the center Scan button.
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

  // Center raised "Scan" button — always uses the CURRENT home's context
  // (widget.homeId / widget.address / widget.pincode), not whatever the
  // last _goToScan() call left behind, so tapping it directly from the
  // nav bar always scans into the home the user is actually in.
  Widget _scanButton() {
    final selected = _currentIndex == _Slot.scan;
    return InkWell(
      onTap: () => _goToScan(
        homeId: widget.homeId,
        address: widget.address,
        pincode: widget.pincode,
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