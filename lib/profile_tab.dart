// lib/profile_tab.dart
//
// Full-page "My Profile" screen — gradient hero card, quick stats,
// protection plan (AMC), homes list, and grouped account-actions cards.
//
// SKIP-FLOW BEHAVIOUR: when the user has no registered home yet (they hit
// "Skip" during address setup), we show a trimmed-down view — just the
// hero card, an "Add home" button, and Account Actions (Sign out).
// Once a real home exists, the full profile renders.
//
// NOTE ON DATA SOURCES:
//  - Device count / homes list come straight from the same Hive box
//    ('homes') that HomeTab already keeps in sync — no extra network call.
//  - "Service requests", "Saved via warranty" and the AMC/protection-plan
//    block are optional constructor inputs with a graceful fallback state.

import 'package:flutter/material.dart';
import 'constants/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'models/home_model.dart';
import 'constants/api_config.dart';
import 'services/session_manager.dart';
import 'services/entity_update_service.dart';
import 'login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/confirm_action_dialog.dart';
import 'home_tab.dart' show ScanRequest;
import 'address_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'services/member_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'services/api_client.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/device_id_service.dart';
import 'dart:io';
import 'widgets/theme_mode_toggle.dart';
import 'utils/warranty_utils.dart';

// Optional, backend-fed extras. Leave null/default until you have a real
// source for them — the UI degrades gracefully either way.
class ProfileStats {
  final int? serviceRequests;
  final num? savedViaWarranty;
  const ProfileStats({this.serviceRequests, this.savedViaWarranty});
}

class AmcPlan {
  final String label; // e.g. "AMC — 10 Appliances"
  final bool active;
  final int slotsUsed;
  final int slotsTotal;
  final DateTime renewsOn;
  final int upgradeToSlots;

  const AmcPlan({
    required this.label,
    required this.active,
    required this.slotsUsed,
    required this.slotsTotal,
    required this.renewsOn,
    this.upgradeToSlots = 25,
  });
}

class ProfileTab extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final DateTime? memberSince;
  final bool verified;
  final ProfileStats stats;
  final AmcPlan? amcPlan;
  final ScanRequest? onScanTap;
  final ValueChanged<String>? onNameChanged;

  const ProfileTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.memberSince,
    this.verified = false,
    this.stats = const ProfileStats(),
    this.amcPlan,
    this.onScanTap,
    this.onNameChanged,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _homeBox = Hive.box<HomeModel>('homes');

  late String _displayName = widget.name;

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _displayName = widget.name;
  }

  int _totalDevices(List<HomeModel> homes) {
    int total = 0;
    for (final h in homes) {
      final map = h.toMap();
      final rooms = (map['rooms'] as Map?) ?? {};
      rooms.forEach((_, items) {
        if (items is List) total += items.length;
      });
    }
    return total;
  }

  int _deviceCountForHome(Map<String, dynamic> home) {
    final rooms = (home['rooms'] as Map?) ?? {};
    int total = 0;
    rooms.forEach((_, items) {
      if (items is List) total += items.length;
    });
    return total;
  }

  // Same "Default" check as HomeTab — a home is still the auto-created
  // placeholder from Skip if its address is exactly 'Default'.
  bool _isDefaultHome(Map<String, dynamic> home) {
    final addr = home['address']?.toString().trim().toLowerCase() ?? '';
    return addr == 'default';
  }

  List<Map<String, dynamic>> _registeredHomes(List<Map<String, dynamic>> homes) =>
      homes.where((h) => !_isDefaultHome(h)).toList();

  Map<String, dynamic>? _findDefaultHome(List<Map<String, dynamic>> homes) {
    for (final h in homes) {
      if (_isDefaultHome(h)) return h;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // EDIT NAME
  // ---------------------------------------------------------------------
  void _openEditProfileDialog() {
    final nameController = TextEditingController(text: _displayName);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: AppDecor.dialogShape,
          title: Text(AppStrings.editProfile, style: AppText.dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppDialogField(controller: nameController, hint: AppStrings.fullName),
              const SizedBox(height: 10),
              Text(widget.mobileNumber, style: AppText.caption),
            ],
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
                      final value = nameController.text.trim();
                      if (value.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text(AppStrings.enterName)),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      // updateEntity (backend) requires homeId as the root
                      // anchor — pick the first available home (registered
                      // or still "Default") to anchor the name update to.
                      final allHomes = _homeBox.values.map((h) => h.toMap()).toList();
                      final homeId = allHomes.isNotEmpty ? allHomes.first['id']?.toString() : null;

                      if (homeId == null) {
                        setState(() => _displayName = value);
                        widget.onNameChanged?.call(value);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text(AppStrings.nameSavedSyncLater)),
                          );
                        }
                        return;
                      }

                      final result = await EntityUpdateService.update(
                        homeId: homeId,
                        name: value,
                      );

                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!mounted) return;

                      if (result['success'] == true) {
                        setState(() => _displayName = value);
                        widget.onNameChanged?.call(value);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(result['success'] == true
                                ? AppStrings.nameUpdated
                                : (result['message']?.toString() ?? AppStrings.nameUpdateFailed))),
                      );
                    },
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                  : Text(AppStrings.save, style: TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ADD HOME / EDIT ADDRESS  (mirrors HomeTab's flows)
  // ---------------------------------------------------------------------
  Future<void> _openAddHomeDialog() async {
    // If a "Default" home already exists (created silently by Skip+Scan),
    // registering should UPDATE that same home instead of creating a new
    // one — otherwise already-scanned devices get orphaned.
    final allHomes = _homeBox.values.map((h) => h.toMap()).toList();
    final defaultHome = _findDefaultHome(allHomes);
    final existingDefaultId = defaultHome?['id']?.toString();

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

    final address = result['address']?.toString();
    final pincode = result['pincode']?.toString();
    if (address == null || address.isEmpty) return;

    if (existingDefaultId != null) {
      // Promote the existing Default home in place.
      final updateResult = await EntityUpdateService.update(
        homeId: existingDefaultId,
        address: address,
        pincode: pincode != null && pincode.isNotEmpty ? pincode : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updateResult['success'] == true
              ? AppStrings.homeRegistered
              : (updateResult['message']?.toString() ?? AppStrings.homeRegisterFailed)),
        ),
      );
      setState(() {}); // Hive listener refreshes once HomeTab re-fetches
      return;
    }

    // No default home yet — genuine "add a new home" path.
    final newHomeId = await _createNewHomeRecord(
      address: address,
      pincode: pincode ?? '',
      name: widget.name,
      homeName: address.split(',').first.trim().isNotEmpty ? address.split(',').first.trim() : 'Home',
    );

    if (!mounted) return;

    if (newHomeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.couldNotCreateHome)),
      );
      return;
    }

    setState(() {}); // Hive listener refreshes once created
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.homeAdded)),
    );
  }

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.signInAgainToAddHome)),
          );
        }
        return null;
      }
      final response = await ApiClient.post(ApiConfig.createHomeUrl, body: {
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
      });
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

  void _openEditAddressDialog(Map<String, dynamic> home) {
    final addressController = TextEditingController(text: home['address']?.toString() ?? '');
    final pincodeController = TextEditingController(text: home['pincode']?.toString() ?? '');
    final homeId = home['id']?.toString();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: AppDecor.dialogShape,
          title: Text(AppStrings.editAddress, style: AppText.dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppDialogField(controller: addressController, hint: AppStrings.address),
              const SizedBox(height: 10),
              AppDialogField(
                  controller: pincodeController,
                  hint: AppStrings.pincode,
                  keyboardType: TextInputType.number,
                  maxLength: 6),
            ],
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
                      if (newAddress.isEmpty || homeId == null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text(AppStrings.enterAddress)));
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      final result = await EntityUpdateService.update(
                        homeId: homeId,
                        address: newAddress,
                        pincode: newPincode.isNotEmpty ? newPincode : null,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (!mounted) return;
                      if (result['success'] == true) {
                        await _refreshHomes();
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(result['success'] == true
                                ? AppStrings.addressUpdated
                                : (result['message']?.toString() ?? AppStrings.addressUpdateFailed))),
                      );
                    },
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                  : Text(AppStrings.save, style: TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SIMPLE "COMING SOON" ROW DESTINATION for sections with no backend yet
  // ---------------------------------------------------------------------
  void _openComingSoon(String title, String subtitle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.dialogTitle),
            const SizedBox(height: 6),
            Text(subtitle, style: AppText.faintCaption),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(AppStrings.gotIt, style: TextStyle(color: AppColors.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReferSheet() {
    const referralMessage = AppStrings.referralMessage;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: Text(AppStrings.referNeighbour, style: AppText.dialogTitle),
        content: Text(
          AppStrings.referNeighbourDesc,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.close, style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: referralMessage));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.referralCopied)),
              );
            },
            icon: Icon(Icons.copy_rounded, size: 16, color: AppColors.textPrimary),
            label: Text(AppStrings.copyLink, style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SIGN OUT
  // ---------------------------------------------------------------------
  Future<void> _handleLogout() async {
    final confirm = await showConfirmActionDialog(
      context,
      title: AppStrings.logOutQ,
      content: AppStrings.logOutContent,
      confirmLabel: AppStrings.logOut,
    );
    if (confirm != true) return;
    ApiClient.reset();
    await FirebaseAuth.instance.signOut();
    await SessionManager.clearSession();
    await Hive.box<HomeModel>('homes').clear();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  // ---------------------------------------------------------------------
  // PULL TO REFRESH — re-fetches home/appliance data from backend and
  // updates the shared Hive box, mirroring HomeTab's fetch logic.
  // ---------------------------------------------------------------------
  Future<void> _refreshHomes() async {
    try {
      final plainMobile = ApiConfig.stripCountryCode(widget.mobileNumber);
      final response = await ApiClient.get(
        '${ApiConfig.submissionSearchUrl}?mobile=$plainMobile',
      );

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
                rooms[roomName.toLowerCase()] =
                    devicesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              }
            } else if (roomsRaw is Map) {
              roomsRaw.forEach((key, value) {
                if (value is List) {
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

          await _homeBox.clear();
          for (final h in parsedHomes) {
            await _homeBox.add(HomeModel.fromMap(h));
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Profile refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.couldNotRefresh)),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<HomeModel>>(
      valueListenable: _homeBox.listenable(),
      builder: (context, box, _) {
        final allHomes = box.values.map((h) => h.toMap()).toList();
        final homes = _registeredHomes(allHomes); // Default home excluded from display
        final totalDevices = _totalDevices(box.values.toList());
        // Skip-flow users have no registered home yet — trimmed view.
        final hasHome = homes.isNotEmpty;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.cardBg,
              onRefresh: _refreshHomes,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroCard(),

                    if (!hasHome) ...[
                      // ============= SKIP-FLOW — trimmed view =============
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openAddHomeDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: AppColors.borderMuted),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(Icons.add_home_rounded, color: AppColors.primary, size: 18),
                          label: Text(AppStrings.addHome,
                              style: TextStyle(
                                  color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader(AppStrings.appearance),
                      const SizedBox(height: 10),
                      const ThemeModeToggle(),
                      const SizedBox(height: 22),
                      _sectionHeader(AppStrings.accountActions, color: AppColors.danger),
                      const SizedBox(height: 10),
                      _groupCard([
                        _accountRow(
                          icon: Icons.logout_rounded,
                          iconColor: AppColors.danger,
                          title: AppStrings.signOut,
                          titleColor: AppColors.danger,
                          onTap: _handleLogout,
                        ),
                      ]),
                    ] else ...[
                      // ============= FULL PROFILE — real home exists =============
                      const SizedBox(height: 22),
                      _buildStatsRow(totalDevices),
                      const SizedBox(height: 24),
                      _buildHouseholdSection(homes),
                      const SizedBox(height: 24),
                      _sectionHeader(AppStrings.myProtectionPlan),
                      const SizedBox(height: 10),
                      _buildProtectionPlan(),
                      const SizedBox(height: 24),
                      _sectionHeader(AppStrings.myHomes),
                      const SizedBox(height: 10),
                      ..._buildHomesList(homes),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openAddHomeDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: AppColors.borderMuted),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(Icons.add_home_rounded, color: AppColors.primary, size: 18),
                          label: Text(AppStrings.addAnotherHome,
                              style: TextStyle(
                                  color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _sectionHeader(AppStrings.appearance),
                      const SizedBox(height: 10),
                      const ThemeModeToggle(),
                      const SizedBox(height: 24),

                      _sectionHeader(AppStrings.myStuff),
                      const SizedBox(height: 10),
                      _groupCard([
                        _accountRow(
                          icon: Icons.shield_outlined,
                          iconColor: AppColors.success,
                          title: AppStrings.warrantyVault,
                          subtitle: _warrantyVaultSubtitle(homes),
                          onTap: () => _openComingSoon(AppStrings.warrantyVault,
                              AppStrings.warrantyVaultDesc),
                        ),
                        _accountRow(
                          icon: Icons.description_outlined,
                          iconColor: AppColors.primary,
                          title: AppStrings.documentLocker,
                          subtitle: AppStrings.documentLockerSub,
                          trailing: _chipLabel(AppStrings.documentLockerChip),
                          onTap: () => _openComingSoon(AppStrings.documentLocker,
                              AppStrings.documentLockerDesc),
                        ),
                        _accountRow(
                          icon: Icons.notifications_outlined,
                          iconColor: AppColors.warning,
                          title: AppStrings.reminders,
                          subtitle: AppStrings.remindersSub,
                          onTap: () => _openComingSoon(AppStrings.reminders,
                              AppStrings.remindersDesc),
                        ),
                      ]),
                      const SizedBox(height: 24),

                      _sectionHeader(AppStrings.rewardsBilling),
                      const SizedBox(height: 10),
                      _groupCard([
                        _accountRow(
                          icon: Icons.people_outline_rounded,
                          iconColor: AppColors.primary,
                          title: AppStrings.referNeighbourRow,
                          subtitle: AppStrings.referNeighbourSub,
                          trailing: _chipLabel(AppStrings.referNeighbourChip),
                          onTap: _openReferSheet,
                        ),
                        _accountRow(
                          icon: Icons.credit_card_outlined,
                          iconColor: AppColors.success,
                          title: AppStrings.paymentsBilling,
                          subtitle: AppStrings.paymentsBillingSub,
                          onTap: () => _openComingSoon(AppStrings.paymentsBilling,
                              AppStrings.paymentsBillingDesc),
                        ),
                      ]),
                      const SizedBox(height: 24),

                      _sectionHeader(AppStrings.supportSection),
                      const SizedBox(height: 10),
                      _groupCard([
                        _accountRow(
                          icon: Icons.settings_outlined,
                          iconColor: AppColors.textSecondary,
                          title: AppStrings.preferences,
                          subtitle: AppStrings.preferencesSub,
                          onTap: () => _openComingSoon(
                              AppStrings.preferences, AppStrings.preferencesDesc),
                        ),
                        _accountRow(
                          icon: Icons.help_outline_rounded,
                          iconColor: AppColors.primary,
                          title: AppStrings.helpSupport,
                          subtitle: AppStrings.helpSupportSub,
                          onTap: () => _openComingSoon(AppStrings.helpSupport,
                              AppStrings.helpSupportDesc),
                        ),
                        _accountRow(
                          icon: Icons.info_outline_rounded,
                          iconColor: AppColors.textMuted,
                          title: AppStrings.aboutZhini,
                          subtitle: AppStrings.aboutZhiniSub,
                          onTap: () => _openComingSoon(AppStrings.aboutZhini,
                              AppStrings.aboutZhiniDesc),
                        ),
                      ]),
                      const SizedBox(height: 24),

                      _groupCard([
                        _accountRow(
                          icon: Icons.logout_rounded,
                          iconColor: AppColors.danger,
                          title: AppStrings.signOut,
                          titleColor: AppColors.danger,
                          onTap: _handleLogout,
                        ),
                      ]),
                    ],

                    const SizedBox(height: 22),
                    Center(
                      child: Text(AppStrings.profileFooter,
                          style: AppText.faintCaption, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: InkWell(
                        onTap: () async {
                          final Uri emailUri = Uri(
                            scheme: 'mailto',
                            path: AppStrings.supportEmail,
                            query: 'subject=ZHINI App Support',
                          );
                          try {
                            await launchUrl(emailUri);
                          } catch (e) {
                            debugPrint('Email launch error: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text(AppStrings.couldNotOpenMail)),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                          child: Text(
                            AppStrings.poweredBy,
                            style: TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // HERO CARD (replaces old header + avatar card)
  // ---------------------------------------------------------------------
  Widget _buildHeroCard() {
    final name = _displayName.trim();
    final hasName = name.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(AppStrings.myProfile,
                  style: TextStyle(
                      color: AppColors.onPrimary.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
              const Spacer(),
              InkWell(
                onTap: _openEditProfileDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 13, color: AppColors.onPrimary),
                      const SizedBox(width: 5),
                      Text(AppStrings.edit,
                          style: TextStyle(
                              color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.onPrimary.withValues(alpha: 0.3),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.onPrimary,
                  child: hasName
                      ? Text(name[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 24, color: AppColors.primary, fontWeight: FontWeight.w800))
                      : Icon(Icons.person_rounded, color: AppColors.primary, size: 28),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasName ? name : AppStrings.addYourName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone_iphone_rounded,
                            size: 13, color: AppColors.onPrimary.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(widget.mobileNumber,
                            style: TextStyle(
                                color: AppColors.onPrimary.withValues(alpha: 0.85), fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.verified || widget.memberSince != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.verified) _heroChip(Icons.verified_rounded, AppStrings.verified),
                if (widget.memberSince != null)
                  _heroChip(Icons.calendar_month_rounded, AppStrings.sinceDate(_monthYear(widget.memberSince!))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onPrimary),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HOUSEHOLD
  // ---------------------------------------------------------------------
  Widget _buildHouseholdSection(List<Map<String, dynamic>> homes) {
    final currentHome = homes.isNotEmpty ? homes.first : null;
    final members = (currentHome?['members'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final myPlain = ApiConfig.stripCountryCode(widget.mobileNumber);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(AppStrings.household),
        const SizedBox(height: 10),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(AppStrings.noMembersYet, style: AppText.faintCaption),
          )
        else
          ...members.map((m) {
            final name = m['name']?.toString() ?? AppStrings.member;
            final mobile = m['mobile']?.toString() ?? '';
            final isMe = mobile == myPlain;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.memberAvatarBg,
                    child: Icon(Icons.person, color: AppColors.textPrimary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isMe ? AppStrings.youSuffix(name) : name,
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                        Text(isMe ? AppStrings.owner : AppStrings.member, style: AppText.caption),
                      ],
                    ),
                  ),
                  Text(mobile, style: AppText.caption),
                  if (!isMe) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _confirmDeleteMember(currentHome, name, mobile),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: currentHome == null ? null : () => _openAddMemberDialog(currentHome),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              side: BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.person_add, color: AppColors.primary, size: 18),
            label: Text(AppStrings.addMember, style: TextStyle(color: AppColors.primary, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  void _openAddMemberDialog(Map<String, dynamic> currentHome) {
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
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppStrings.contactsPermissionDenied)),
                );
                return;
              }
              final contact = await FlutterContacts.openExternalPick();
              if (contact == null) return;

              final full = await FlutterContacts.getContact(contact.id);
              if (full == null) return;

              String phone = full.phones.isNotEmpty ? full.phones.first.number : '';
              phone = phone.replaceAll(RegExp(r'\D'), '');
              if (phone.length > 10) phone = phone.substring(phone.length - 10);

              if (phone.length != 10) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStrings.noValid10Digit)),
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
              title: Text(AppStrings.addMember, style: AppText.dialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.addMemberDesc,
                    style: AppText.faintCaption,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: pickFromContacts,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(Icons.contacts_rounded, color: AppColors.primary, size: 18),
                      label: Text(AppStrings.pickFromContacts, style: TextStyle(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                          CircleAvatar(
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
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                                Text(pickedMobile!, style: AppText.caption),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => setDialogState(() {
                              pickedName = null;
                              pickedMobile = null;
                            }),
                            child: Icon(Icons.close, color: AppColors.textFaint, size: 18),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(AppStrings.noContactSelected, style: AppText.faintCaption),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: (isSubmitting || pickedName == null || pickedMobile == null)
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          await _submitAddMember(currentHome, pickedName!, pickedMobile!);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        },
                  child: isSubmitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : Text(AppStrings.add, style: TextStyle(color: AppColors.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitAddMember(Map<String, dynamic> currentHome, String name, String newMobile) async {
    final homeId = currentHome['id']?.toString();
    if (homeId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.noHomeSelected)),
        );
      }
      return;
    }

    final myMobile = ApiConfig.stripCountryCode(widget.mobileNumber);
    final result = await MemberService.addMember(
      homeId: homeId,
      myMobile: myMobile,
      newName: name,
      newMobile: newMobile,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['message']?.toString() ?? '')),
    );

    if (result['success'] == true) {
      await MemberService.refreshHomeMembers(homeId: homeId, mobileNumber: widget.mobileNumber);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDeleteMember(
      Map<String, dynamic>? currentHome, String name, String mobile) async {
    final homeId = currentHome?['id']?.toString();
    if (homeId == null) return;
    final confirm = await showConfirmActionDialog(
      context,
      title: AppStrings.removeMemberQ,
      content: AppStrings.memberLosesAccess(name),
    );
    if (confirm != true) return;

    final result = await MemberService.deleteMember(homeId: homeId, mobile: mobile);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(result['success'] == true ? AppStrings.memberRemoved(name) : (result['message']?.toString() ?? ''))),
    );

    if (result['success'] == true) {
      await MemberService.refreshHomeMembers(homeId: homeId, mobileNumber: widget.mobileNumber);
      if (mounted) setState(() {});
    }
  }

  String _warrantyVaultSubtitle(List<Map<String, dynamic>> homes) {
    int active = 0;
    int expired = 0;
    for (final h in homes) {
      final rooms = (h['rooms'] as Map?) ?? {};
      rooms.forEach((_, items) {
        if (items is! List) return;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final expiry = WarrantyUtils.parseExpiry(
  item['warranty']?.toString(),
  referenceDate: DateTime.tryParse(item['createdAt']?.toString() ?? ''),
);
          if (expiry != null && expiry.isAfter(DateTime.now())) {
            active++;
          } else if (expiry != null) {
            expired++;
          }
        }
      });
    }
    return AppStrings.warrantyVaultSubtitle(active, expired);
  }

  String _monthYear(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.year}';
  }

  // ---------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------
  Widget _buildStatsRow(int totalDevices) {
    Widget box(IconData icon, Color color, String value, String label) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: AppDecor.flatCard(radius: 16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        box(Icons.devices_other_rounded, AppColors.primary, '$totalDevices', 'Devices\nregistered'),
        box(
            Icons.build_circle_outlined,
            AppColors.warning,
            widget.stats.serviceRequests != null ? '${widget.stats.serviceRequests}' : '—',
            'Service\nrequests'),
        box(
            Icons.savings_outlined,
            AppColors.success,
            widget.stats.savedViaWarranty != null ? '₹${_compact(widget.stats.savedViaWarranty!)}' : '—',
            AppStrings.statSavedViaWarranty),
      ],
    );
  }

  String _compact(num value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    return value.toStringAsFixed(0);
  }

  // ---------------------------------------------------------------------
  // PROTECTION PLAN
  // ---------------------------------------------------------------------
  Widget _buildProtectionPlan() {
    final plan = widget.amcPlan;
    if (plan == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryFaint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.noActiveProtectionPlan,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(AppStrings.coverAllAppliancesAmc, style: AppText.faintCaption),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openComingSoon(AppStrings.protectionPlans,
                  AppStrings.protectionPlansDesc),
              child: Text(AppStrings.explore, style: AppText.linkAction),
            ),
          ],
        ),
      );
    }

    final daysLeft = plan.renewsOn.difference(DateTime.now()).inDays;
    final progress = plan.slotsTotal == 0 ? 0.0 : (plan.slotsUsed / plan.slotsTotal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plan.label,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (plan.active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(AppStrings.activeBadge,
                      style: TextStyle(
                          color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.slotsUsed(plan.slotsUsed, plan.slotsTotal, _monthYear(plan.renewsOn)),
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.borderSubtle,
              valueColor: AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppStrings.daysRemaining(daysLeft), style: AppText.caption),
              TextButton(
                onPressed: () => _openComingSoon(
                    AppStrings.upgradePlan, AppStrings.upgradePlanDesc(plan.upgradeToSlots)),
                child: Text(AppStrings.upgradeTo(plan.upgradeToSlots), style: AppText.linkAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HOMES LIST
  // ---------------------------------------------------------------------
  List<Widget> _buildHomesList(List<Map<String, dynamic>> homes) {
    if (homes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(AppStrings.noHomesYet, style: AppText.faintCaption),
        ),
      ];
    }
    return homes.asMap().entries.map((entry) {
      final home = entry.value;
      final address = home['address']?.toString() ?? '';
      final title = address.isNotEmpty ? address.split(',').first.trim() : AppStrings.homeN(entry.key + 1);
      final locality = address.contains(',') ? address.split(',').skip(1).join(',').trim() : '';
      final deviceCount = _deviceCountForHome(home);
      final isSelected = entry.key == 0;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.6) : AppColors.borderSubtle,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSelected ? AppColors.primary : AppColors.textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(isSelected ? Icons.home_rounded : Icons.home_outlined,
                  size: 22, color: isSelected ? AppColors.primary : AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(AppStrings.primaryBadge,
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6)),
                        ),
                      ],
                    ],
                  ),
                  if (locality.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(locality, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  ],
                  const SizedBox(height: 4),
                  Text(AppStrings.devicesAmc(deviceCount, isSelected),
                      style: AppText.caption),
                ],
              ),
            ),
            InkWell(
              onTap: () => _openEditAddressDialog(home),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: Icon(Icons.edit_outlined, color: AppColors.primary, size: 16),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------
  // SHARED UI HELPERS
  // ---------------------------------------------------------------------
  Widget _sectionHeader(String title, {Color color = AppColors.textMuted}) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: color == AppColors.textMuted ? AppColors.primary : color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ],
    );
  }

  Widget _chipLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }

  // Rows ah oru card kulla vechu, naduvula divider podum.
  Widget _groupCard(List<Widget> rows) {
    return Container(
      decoration: AppDecor.flatCard(radius: 18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(height: 1, indent: 62, endIndent: 14, color: AppColors.borderSubtle),
          ],
        ],
      ),
    );
  }

  Widget _accountRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color titleColor = AppColors.textPrimary,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[trailing, const SizedBox(width: 6)],
            Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}