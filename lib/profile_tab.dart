// lib/profile_tab.dart
//
// Full-page "My Profile" screen — avatar/verification header, quick stats,
// protection plan (AMC), homes list, and a grouped account-actions list.
//
// SKIP-FLOW BEHAVIOUR: when the user has no registered home yet (they hit
// "Skip" during address setup), we show a trimmed-down view — just the
// profile card, an "Add home" button, and Account Actions (Sign out).
// Once a real home exists, the full profile (household, stats, protection
// plan, homes list, full account menu) renders exactly as before.
//
// NOTE ON DATA SOURCES:
//  - Device count / homes list come straight from the same Hive box
//    ('homes') that HomeTab already keeps in sync — no extra network call.
//  - "Service requests", "Saved via ₹warranty" and the AMC/protection-plan
//    block have no backend field in the code shared with me, so they're
//    wired as optional constructor inputs with a graceful empty/fallback
//    state instead of being faked. Pass real values in once you have an
//    endpoint for them (see `ProfileStats` / `AmcPlan` below).
//  - "Delete account" has no known endpoint yet — the button is fully
//    wired up to a confirm dialog; hook `_deleteAccount()` up to your real
//    endpoint when it exists (marked with a TODO).

import 'package:flutter/material.dart';
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
import 'services/member_service.dart'; // 👈 add this import

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
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _homeBox = Hive.box<HomeModel>('homes');
  late String _displayName = widget.name;

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
          title: const Text('Edit Profile', style: AppText.dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppDialogField(controller: nameController, hint: 'Full name'),
              const SizedBox(height: 10),
              Text(widget.mobileNumber, style: AppText.caption),
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
                      final value = nameController.text.trim();
                      if (value.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a name.')),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      // updateEntity (backend) requires homeId as the root
                      // anchor — pick the first available home (registered
                      // or still "Default") to anchor the name update to.
                      // No home at all yet -> nothing to anchor to, so we
                      // just save locally and sync once a home exists.
                      final allHomes = _homeBox.values.map((h) => h.toMap()).toList();
                      final homeId = allHomes.isNotEmpty ? allHomes.first['id']?.toString() : null;

                      if (homeId == null) {
                        setState(() => _displayName = value);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Name saved. It will sync once you register a home.')),
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
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result['success'] == true
                            ? 'Name updated successfully ✅'
                            : (result['message']?.toString() ?? 'Failed to update name'))),
                      );
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
  // ADD HOME / EDIT ADDRESS  (mirrors HomeTab's flows)
  // ---------------------------------------------------------------------
Future<void> _openAddHomeDialog() async {
    // If a "Default" home already exists (created silently by Skip+Scan),
    // registering should UPDATE that same home instead of creating a new
    // one — otherwise already-scanned devices get orphaned. Mirrors
    // HomeTab._openAddHomeDialog's logic.
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
              ? 'Home registered successfully ✅'
              : (updateResult['message']?.toString() ?? 'Failed to register home')),
        ),
      );
      setState(() {}); // Hive listener refreshes once HomeTab re-fetches
      return;
    }

    // No default home yet — genuine "add a new home" path.
    widget.onScanTap?.call(homeId: null, address: address, pincode: pincode ?? '');
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
          title: const Text('Edit Address', style: AppText.dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppDialogField(controller: addressController, hint: 'Address'),
              const SizedBox(height: 10),
              AppDialogField(controller: pincodeController, hint: 'Pincode', keyboardType: TextInputType.number, maxLength: 6),
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
                      if (newAddress.isEmpty || homeId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the address.')));
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result['success'] == true
                            ? 'Address updated successfully ✅'
                            : (result['message']?.toString() ?? 'Failed to update address'))),
                      );
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
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
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Got it', style: TextStyle(color: AppColors.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReferSheet() {
    const referralMessage =
        "Hey! I've been using ZHINI to track all my home appliances, warranties, and find repair services in one place. Try it out 👉 https://zhini.app/download";
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text('Refer a Neighbour', style: AppText.dialogTitle),
        content: const Text(
          "Share ZHINI with a neighbour — they'll be able to track their own home's appliances too.",
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
  // SIGN OUT / DELETE ACCOUNT
  // ---------------------------------------------------------------------
  Future<void> _handleLogout() async {
    final confirm = await showConfirmActionDialog(
      context,
      title: 'Log out?',
      content: "You'll need to verify your mobile number when you sign in again.",
      confirmLabel: 'Log out',
    );
    if (confirm != true) return;

    await SessionManager.clearSession();
    await Hive.box<HomeModel>('homes').clear();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
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
final homes = _registeredHomes(allHomes);   // 👈 Default home excluded from display
final totalDevices = _totalDevices(box.values.toList());
// Skip-flow users (or Skip+Scan with only a "Default" home) have no
// registered home yet — show the trimmed view until they register.
final hasHome = homes.isNotEmpty;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 18),
                        _buildAvatarCard(),

                        if (!hasHome) ...[
                          // ============= SKIP-FLOW — trimmed view =============
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openAddHomeDialog,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: const BorderSide(color: AppColors.borderMuted),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.add_home_rounded, color: AppColors.primary, size: 18),
                              label: const Text('Add home',
                                  style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _sectionHeader('ACCOUNT ACTIONS', color: AppColors.danger),
                          const SizedBox(height: 10),
                          _accountRow(
                            icon: Icons.logout_rounded,
                            iconColor: AppColors.danger,
                            title: 'Sign out',
                            titleColor: AppColors.danger,
                            onTap: _handleLogout,
                          ),
                        ] else ...[
                          // ============= FULL PROFILE — real home exists =============
                          const SizedBox(height: 18),
                          _buildHouseholdSection(homes),
                          const SizedBox(height: 22),
                          _buildStatsRow(totalDevices),
                          const SizedBox(height: 22),
                          _sectionHeader('MY PROTECTION PLAN'),
                          const SizedBox(height: 10),
                          _buildProtectionPlan(),
                          const SizedBox(height: 22),
                          _sectionHeader('MY HOMES'),
                          const SizedBox(height: 10),
                          ..._buildHomesList(homes),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openAddHomeDialog,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: const BorderSide(color: AppColors.borderMuted),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.add_home_rounded, color: AppColors.primary, size: 18),
                              label: const Text('Add another home', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _sectionHeader('ACCOUNT'),
                          const SizedBox(height: 10),
                          _accountRow(
                            icon: Icons.shield_outlined,
                            iconColor: AppColors.success,
                            title: 'Warranty vault',
                            subtitle: _warrantyVaultSubtitle(homes),
                            onTap: () => _openComingSoon('Warranty vault', 'A full list of active and expired warranties across all your homes will show up here.'),
                          ),
                          _accountRow(
                            icon: Icons.description_outlined,
                            iconColor: AppColors.primary,
                            title: 'Document locker',
                            subtitle: 'Bills · Manuals · Photos',
                            trailing: _chipLabel('14 files'),
                            onTap: () => _openComingSoon('Document locker', 'Upload and store bills, manuals and photos against each appliance.'),
                          ),
                          _accountRow(
                            icon: Icons.notifications_outlined,
                            iconColor: AppColors.warning,
                            title: 'Reminders',
                            subtitle: 'Warranty · Service · AMC',
                            onTap: () => _openComingSoon('Reminders', 'Get notified before warranties expire or a service is due.'),
                          ),
                          _accountRow(
                            icon: Icons.people_outline_rounded,
                            iconColor: AppColors.primary,
                            title: 'Refer a neighbour',
                            subtitle: '2 referrals · ₹200 earned',
                            trailing: _chipLabel('Earn ₹100'),
                            onTap: _openReferSheet,
                          ),
                          _accountRow(
                            icon: Icons.credit_card_outlined,
                            iconColor: AppColors.success,
                            title: 'Payments and billing',
                            subtitle: 'UPI · Cards · History',
                            onTap: () => _openComingSoon('Payments and billing', 'Manage saved payment methods and view your billing history.'),
                          ),
                          _accountRow(
                            icon: Icons.settings_outlined,
                            iconColor: AppColors.textSecondary,
                            title: 'Preferences',
                            subtitle: 'Language · Notifications · Theme',
                            onTap: () => _openComingSoon('Preferences', 'App language, notification and theme settings.'),
                          ),
                          _accountRow(
                            icon: Icons.help_outline_rounded,
                            iconColor: AppColors.primary,
                            title: 'Help and support',
                            subtitle: 'FAQ · Chat · Call ZHINI',
                            onTap: () => _openComingSoon('Help and support', 'Reach ZHINI support via chat, call, or browse the FAQ.'),
                          ),
                          _accountRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppColors.textMuted,
                            title: 'About ZHINI',
                            subtitle: 'v1.0.0 · Built by two kids',
                            onTap: () => _openComingSoon('About ZHINI', 'ZHINI v1.0.0 — your home\'s appliance and warranty companion.'),
                          ),
                          const SizedBox(height: 22),
                          _sectionHeader('ACCOUNT ACTIONS', color: AppColors.danger),
                          const SizedBox(height: 10),
                          _accountRow(
                            icon: Icons.logout_rounded,
                            iconColor: AppColors.danger,
                            title: 'Sign out',
                            titleColor: AppColors.danger,
                            onTap: _handleLogout,
                          ),
                        ],

                        const SizedBox(height: 18),
                        Center(
                          child: Text('Your data is never sold · DPDP compliant · v1.0.0',
                              style: AppText.faintCaption, textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: _buildAskZhiniBar(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
        _sectionHeader('HOUSEHOLD'),
        const SizedBox(height: 10),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('No members added yet.', style: AppText.faintCaption),
          )
        else
          ...members.map((m) {
            final name = m['name']?.toString() ?? 'Member';
            final mobile = m['mobile']?.toString() ?? '';
            final isMe = mobile == myPlain;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
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
                        Text(isMe ? '$name (You)' : name,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                        Text(isMe ? 'Owner' : 'Member', style: AppText.caption),
                      ],
                    ),
                  ),
                  Text(mobile, style: AppText.caption),
                  if (!isMe) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _confirmDeleteMember(currentHome, name, mobile),
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
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: currentHome == null ? null : () => _openAddMemberDialog(currentHome),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.person_add, color: AppColors.primary, size: 18),
            label: const Text('Add Member', style: TextStyle(color: AppColors.primary, fontSize: 14)),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contacts permission denied.')),
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
                                Text(pickedName!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
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
                          await _submitAddMember(currentHome, pickedName!, pickedMobile!);
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

Future<void> _submitAddMember(Map<String, dynamic> currentHome, String name, String newMobile) async {
    final homeId = currentHome['id']?.toString();
    if (homeId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No home selected. Please select a home first.')),
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
      if (mounted) setState(() {}); // box already patched, this just repaints
    }
  }

  Future<void> _confirmDeleteMember(Map<String, dynamic>? currentHome, String name, String mobile) async {
    final homeId = currentHome?['id']?.toString();
    if (homeId == null) return;
    final confirm = await showConfirmActionDialog(
      context,
      title: 'Remove member?',
      content: '$name will lose access to this home.',
    );
    if (confirm != true) return;

    final result = await MemberService.deleteMember(homeId: homeId, mobile: mobile);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['success'] == true ? '$name removed ✅' : (result['message']?.toString() ?? ''))),
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
          final expiry = WarrantyUtilsLite.parseExpiry(item);
          if (expiry != null && expiry.isAfter(DateTime.now())) {
            active++;
          } else if (expiry != null) {
            expired++;
          }
        }
      });
    }
    return '$active active · $expired expired';
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Account · Homes · Settings', style: AppText.caption),
            ],
          ),
        ),
        InkWell(
          onTap: _openEditProfileDialog,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
              SizedBox(width: 4),
              Text('Edit', style: AppText.linkAction),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarCard() {
    final trimmedName = _displayName.trim();
    final hasName = trimmedName.isNotEmpty;
    final memberSinceText = widget.memberSince != null
        ? 'Member since ${_monthYear(widget.memberSince!)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecor.flatCard(radius: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary,
            // 👈 No more hardcoded 'P' fallback — shows a generic person
            // icon when there's no real name yet, and the actual initial
            // once a name is set.
            child: hasName
                ? Text(trimmedName[0].toUpperCase(),
                    style: const TextStyle(fontSize: 20, color: AppColors.textPrimary, fontWeight: FontWeight.bold))
                : const Icon(Icons.person_rounded, color: AppColors.textPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasName ? trimmedName : 'Add your name',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(widget.mobileNumber, style: AppText.caption),
                if (memberSinceText != null) ...[
                  const SizedBox(height: 2),
                  Text(memberSinceText, style: AppText.caption),
                ],
                if (widget.verified) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
                        SizedBox(width: 4),
                        Text('Verified account', style: TextStyle(color: AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _monthYear(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.year}';
  }

  Widget _buildStatsRow(int totalDevices) {
    Widget box(String value, String label) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: AppDecor.flatCard(radius: 12),
          child: Column(
            children: [
              Text(value, style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        box('$totalDevices', 'Devices\nregistered'),
        box(widget.stats.serviceRequests != null ? '${widget.stats.serviceRequests}' : '—', 'Service\nrequests'),
        box(widget.stats.savedViaWarranty != null ? '₹${_compact(widget.stats.savedViaWarranty!)}' : '—', 'Saved via\nwarranty'),
      ],
    );
  }

  String _compact(num value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    return value.toStringAsFixed(0);
  }

  Widget _buildProtectionPlan() {
    final plan = widget.amcPlan;
    if (plan == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryFaint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No active protection plan', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Cover all your appliances under one AMC plan.', style: AppText.faintCaption),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openComingSoon('Protection plans', 'Browse AMC plans that cover repairs and servicing for your appliances.'),
              child: const Text('Explore', style: AppText.linkAction),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plan.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (plan.active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: const Text('ACTIVE', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${plan.slotsUsed} of ${plan.slotsTotal} appliance slots used · Renews ${_monthYear(plan.renewsOn)}',
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.borderSubtle,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$daysLeft days remaining', style: AppText.caption),
              TextButton(
                onPressed: () => _openComingSoon('Upgrade plan', 'Upgrade your AMC to cover up to ${plan.upgradeToSlots} appliances.'),
                child: Text('Upgrade to ${plan.upgradeToSlots} ↗', style: AppText.linkAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHomesList(List<Map<String, dynamic>> homes) {
    if (homes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('No homes yet.', style: AppText.faintCaption),
        ),
      ];
    }
    return homes.asMap().entries.map((entry) {
      final home = entry.value;
      final address = home['address']?.toString() ?? '';
      final title = address.isNotEmpty ? address.split(',').first.trim() : 'Home ${entry.key + 1}';
      final locality = address.contains(',') ? address.split(',').skip(1).join(',').trim() : '';
      final deviceCount = _deviceCountForHome(home);
      final isSelected = entry.key == 0;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary.withValues(alpha: 0.6) : AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.home_rounded : Icons.home_outlined, size: 18,
                color: isSelected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$title${locality.isNotEmpty ? ' — $locality' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$deviceCount devices · ${isSelected ? 'AMC active' : 'No AMC'}', style: AppText.caption),
                ],
              ),
            ),
            if (isSelected)
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
            else
              InkWell(
                onTap: () => _openEditAddressDialog(home),
                borderRadius: BorderRadius.circular(20),
                child: const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
              ),
          ],
        ),
      );
    }).toList();
  }

  Widget _sectionHeader(String title, {Color color = AppColors.textMuted}) {
    return Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1));
  }

  Widget _chipLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w600)),
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[trailing, const SizedBox(width: 6)],
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAskZhiniBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text('Ask ZHINI about your account…', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Icon(Icons.mic_none_rounded, color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }
}

// Minimal, local warranty-expiry parser used only for the vault subtitle
// count — mirrors WarrantyUtils.parseExpiry's public contract so this file
// has no compile-time dependency ordering surprises. If your project's
// utils/warranty_utils.dart already exposes parseExpiry(String?, {DateTime?
// referenceDate}), feel free to delete this shim and call that directly
// (as the rest of this file already does via `home_tab.dart`'s pattern).
class WarrantyUtilsLite {
  static DateTime? parseExpiry(Map<String, dynamic> item) {
    final warranty = item['warranty']?.toString();
    final createdAt = DateTime.tryParse(item['createdAt']?.toString() ?? '');
    if (warranty == null || warranty.trim().isEmpty || warranty.toUpperCase() == 'N/A') return null;

    final yearMatch = RegExp(r'(\d+)\s*Year').firstMatch(warranty);
    if (yearMatch != null) {
      final years = int.tryParse(yearMatch.group(1) ?? '') ?? 0;
      final base = createdAt ?? DateTime.now();
      return DateTime(base.year + years, base.month, base.day);
    }
    final direct = DateTime.tryParse(warranty);
    if (direct != null) return direct;
    return null;
  }
}