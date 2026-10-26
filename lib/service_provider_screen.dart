import 'dart:convert';
import 'theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'constants/api_config.dart';
import 'service_provider_dashboard.dart';
import 'login_screen.dart';
import 'services/api_client.dart';
import 'services/device_id_service.dart';

class ServiceProviderOnboardingScreen extends StatefulWidget {
  final String mobileNumber;

  // true na backend la user (home) record illa. Submit pannum bodhu
  // mudhalla user-ah create pannitu, appuram provider create pannum.
  final bool createUserFirst;

  const ServiceProviderOnboardingScreen({
    super.key,
    required this.mobileNumber,
    this.createUserFirst = false,
  });

  @override
  State<ServiceProviderOnboardingScreen> createState() =>
      _ServiceProviderOnboardingScreenState();
}

class _ServiceProviderOnboardingScreenState
    extends State<ServiceProviderOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0 = details, 1 = CRM
  static const int _totalSteps = 2;

  File? _storePhoto;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _gstinController = TextEditingController();
  final TextEditingController _othersController = TextEditingController();

  final List<String> _allAppliances = [
    'Plumbing',
    'Electrician',
    'AC Service',
    'Home Appliances',
    'Carpenter',
    'Painting',
    'Others',
  ];
  final Set<String> _selectedAppliances = {};

  // Skill -> sub-services shown after the skill chip is selected.
  static const Map<String, List<String>> _subServices = {
    'AC Service': ['Gas filling', 'Cleaning / Wash', 'Installation', 'Repair', 'Full service'],
    'Plumbing': ['Tap & leak repair', 'Pipe fitting', 'Bathroom fitting', 'Tank cleaning', 'Drain blockage'],
    'Electrician': ['Wiring', 'Switch & socket', 'Fan / light fitting', 'MCB / fuse', 'Full service'],
    'Carpenter': ['Furniture repair', 'Door & window', 'Modular work', 'Polishing', 'Assembly'],
    'Painting': ['Interior', 'Exterior', 'Waterproofing', 'Texture / design', 'Touch-up'],
    'Home Appliances': [
      'Refrigerator', 'Washing Machine', 'Television', 'Microwave Oven',
      'Water Purifier (RO)', 'Geyser / Water Heater', 'Mixer / Grinder',
      'Ceiling / Table Fan', 'Air Cooler', 'Induction / Gas Stove', 'Chimney',
      'Dishwasher', 'Inverter / UPS', 'Vacuum Cleaner', 'Iron Box', 'Wi-Fi Router',
    ],
  };

  final Map<String, Set<String>> _selectedSubs = {};

  double _workingRangeKm = 1;
  bool _isSubmitting = false;

  // User record already created in this session (retry la thirumba create
  // aagaama irukka).
  bool _userCreated = false;

  String get _plainMobile => ApiConfig.stripCountryCode(widget.mobileNumber);

  String get _referralCode {
    final firstName = _nameController.text.trim().isEmpty
        ? 'PARTNER'
        : _nameController.text.trim().split(' ').first.toUpperCase();
    return '$firstName${DateTime.now().year}';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    _gstinController.dispose();
    _othersController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text('Log out?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'You will need to verify your mobile number again.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _pickStorePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _storePhoto = File(picked.path));
    }
  }

  // ---------------- Step navigation ----------------

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onContinueFromStep1() {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Please enter your name');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _showSnack('Please enter your city / service area');
      return;
    }
    if (_pincodeController.text.trim().length != 6) {
      _showSnack('Please enter a valid 6-digit pincode');
      return;
    }
    if (_selectedAppliances.isEmpty) {
      _showSnack('Please select at least one skill');
      return;
    }
    if (_selectedAppliances.contains('Others') &&
        _othersController.text.trim().isEmpty) {
      _showSnack('Please specify your service in "Others"');
      return;
    }
    _goToStep(1);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- Create user (background) ----------------

  /// Backend la user (home) record create pannum. Idhu dhaan user + authToken
  /// DB la save pannum. Success na homeId return pannum, fail na null.
  Future<String?> _createUserRecord() async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (authToken == null) {
        debugPrint('❌ No Firebase auth token — user not signed in?');
        return null;
      }
      final deviceId = await DeviceIdService.getDeviceId();
      final fcmToken = await ApiClient.safeFcmToken();

      final pincode = _pincodeController.text.trim();
      final fullAddress = '${_addressController.text.trim()} - $pincode';

      final response = await http.post(
        Uri.parse(ApiConfig.createHomeUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'x-auth-token': authToken,
          'x-device-id': deviceId,
        },
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'mobile': _plainMobile,
          'address': fullAddress,
          'pincode': pincode,
          'role': 'service_provider',
          'PlatformInfo': {
            'device': {
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'os': Platform.isAndroid ? 'android' : 'ios',
            },
          },
        }),
      );

      debugPrint('🏠 Create user status: ${response.statusCode}');
      debugPrint('🏠 Create user body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['homeId']?.toString();
        }
      }
    } catch (e) {
      debugPrint('❌ Create user error: $e');
    }
    return null;
  }

  // ---------------- Submit ----------------

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      // Step A: user record illa na mudhalla adhai create pannu.
      if (widget.createUserFirst && !_userCreated) {
        final homeId = await _createUserRecord();
        if (homeId == null) {
          if (mounted) {
            _showSnack('Could not create your account. Please try again.');
          }
          return; // finally block _isSubmitting reset pannum
        }
        _userCreated = true;
      }

      // Step B: service provider create.
      final finalExpertise =
          _selectedAppliances.where((e) => e != 'Others').toList();
      if (_selectedAppliances.contains('Others')) {
        final customServices = _othersController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);
        finalExpertise.addAll(customServices);
      }

      final subMap = {
        for (final e in _selectedSubs.entries)
          if (_selectedAppliances.contains(e.key) && e.value.isNotEmpty)
            e.key: e.value.toList(),
      };

      final uri = Uri.parse(ApiConfig.createServiceProviderUrl);
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await ApiClient.authHeaders())
        ..fields['name'] = _nameController.text.trim()
        ..fields['mobile'] = _plainMobile
        ..fields['address'] = _addressController.text.trim()
        ..fields['pincode'] = _pincodeController.text.trim()
        ..fields['range'] = _workingRangeKm.round().toString()
        ..fields['expertise'] = finalExpertise.join(',')
        ..fields['subServices'] = jsonEncode(subMap);

      if (_gstinController.text.trim().isNotEmpty) {
        request.fields['gstNumber'] = _gstinController.text.trim();
      }

      if (_storePhoto != null) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', _storePhoto!.path),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📡 Status: ${response.statusCode}, Body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceProviderDashboard(
              name: _nameController.text.trim(),
              mobileNumber: widget.mobileNumber,
            ),
          ),
          (route) => false,
        );
      } else {
        _showSnack('Registration failed. Please try again.');
      }
    } catch (e) {
      debugPrint('⚠️ Error submitting provider: $e');
      if (!mounted) return;
      _showSnack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep > 0) {
          _goToStep(_currentStep - 1);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.scaffoldBg,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: _currentStep == 0
              ? null
              : IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.textSecondary),
                  onPressed: () => _goToStep(_currentStep - 1),
                ),
          title: Text(
            'Become a service provider',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.logout, color: AppColors.textSecondary),
              onPressed: _logout,
              tooltip: 'Log out',
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepDots(currentStep: _currentStep, totalSteps: _totalSteps),
                const SizedBox(height: 20),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentStep = i),
                    children: [
                      _buildStep1(),
                      _buildStep2(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Step 1: Profile + Store details ----
  Widget _buildStep1() {
    return _StepCard(
      title: 'Your details',
      stepLabel: 'Step 1 of $_totalSteps',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Full name'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: _fieldDecoration('Enter your full name'),
            ),
            const SizedBox(height: 20),
            _label('City / service area'),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              maxLines: 2,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: _fieldDecoration('e.g. Chennai — T. Nagar, Adyar'),
            ),
            const SizedBox(height: 20),
            _label('Pincode'),
            const SizedBox(height: 8),
            TextField(
              controller: _pincodeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: _fieldDecoration('e.g. 600045').copyWith(
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            _label('Skills (select all that apply)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _allAppliances.map((appliance) {
                final isSelected = _selectedAppliances.contains(appliance);
                return _choiceChip(
                  label: appliance,
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedAppliances.remove(appliance);
                        _selectedSubs.remove(appliance);
                      } else {
                        _selectedAppliances.add(appliance);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            // Sub-services for every selected skill that has them
            for (final skill in _allAppliances)
              if (_selectedAppliances.contains(skill) &&
                  _subServices.containsKey(skill))
                _buildSubServiceBlock(skill),

            if (_selectedAppliances.contains('Others')) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _othersController,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                decoration: _fieldDecoration(
                    'e.g. Pest control, Home cleaning (comma separated)'),
              ),
            ],

            // ── Store details (merged from old Step 2) ──
            const SizedBox(height: 24),
            _label('Store photo (optional)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickStorePhoto,
              child: Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryBorder),
                  color: AppColors.textPrimary.withValues(alpha: 0.05),
                ),
                child: _storePhoto == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo,
                              color: AppColors.primary, size: 26),
                          const SizedBox(height: 4),
                          Text('Add photo',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_storePhoto!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            _label('Working range'),
            Center(
              child: Text(
                '${_workingRangeKm.round()} km',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Slider(
              value: _workingRangeKm,
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.textDisabled,
              label: '${_workingRangeKm.round()} km',
              onChanged: (value) => setState(() => _workingRangeKm = value),
            ),
            const SizedBox(height: 12),
            _label('GSTIN (optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _gstinController,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: _fieldDecoration('e.g. 22AAAAA0000A1Z5'),
            ),
            const SizedBox(height: 28),
            _primaryButton('Continue', onPressed: _onContinueFromStep1),
          ],
        ),
      ),
    );
  }

  // ---- Sub-service picker for one skill ----
  Widget _buildSubServiceBlock(String skill) {
    final options = _subServices[skill] ?? const <String>[];
    final selected = _selectedSubs[skill] ?? <String>{};
    final allSelected = options.isNotEmpty && selected.length == options.length;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBgAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$skill — what do you handle?',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      if (allSelected) {
                        _selectedSubs[skill] = <String>{};
                      } else {
                        _selectedSubs[skill] = options.toSet();
                      }
                    });
                  },
                  child: Text(allSelected ? 'Clear' : 'Select all',
                      style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((sub) {
                final isOn = selected.contains(sub);
                return _choiceChip(
                  label: sub,
                  selected: isOn,
                  small: true,
                  onTap: () {
                    setState(() {
                      final set = _selectedSubs.putIfAbsent(skill, () => <String>{});
                      if (isOn) {
                        set.remove(sub);
                      } else {
                        set.add(sub);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Step 2: Free CRM activated ----
  Widget _buildStep2() {
    return _StepCard(
      title: 'Free CRM activated',
      stepLabel: 'Step 2 of $_totalSteps',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ZHINI CRM is free',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Job management · Invoice generation · Customer history',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBgAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Your referral code',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _referralCode,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Earn ₹200 when a colleague joins and completes first job',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _primaryButton(
              'Start receiving jobs',
              onPressed: _isSubmitting ? null : _submit,
              loading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Shared small widgets ----------------

  Widget _label(String text) => Text(
        text,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      );

  /// Rounded selectable chip (skills + sub-services). Theme-aware.
  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool small = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
            horizontal: small ? 12 : 16, vertical: small ? 6 : 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.primaryBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            fontSize: small ? 12 : 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(String text,
      {required VoidCallback? onPressed, bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: loading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: AppColors.onPrimary, strokeWidth: 2),
              )
            : Text(text,
                style: TextStyle(color: AppColors.onPrimary, fontSize: 16)),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primaryBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}

/// Rounded card container used for each onboarding step, with
/// the step title + "Step X of N" subtitle at the top.
class _StepCard extends StatelessWidget {
  final String title;
  final String stepLabel;
  final Widget child;

  const _StepCard({
    required this.title,
    required this.stepLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stepLabel,
            style: TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The small dot + connecting-line progress indicator at the top:
/// completed = green, current = elongated blue pill, upcoming = grey outline.
class _StepDots extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepDots({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < totalSteps; i++) {
      final bool isCompleted = i < currentStep;
      final bool isCurrent = i == currentStep;

      widgets.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 8,
          width: isCurrent ? 26 : 8,
          decoration: BoxDecoration(
            color: isCompleted
                ? AppColors.success
                : (isCurrent ? AppColors.primary : Colors.transparent),
            border: isCurrent || isCompleted
                ? null
                : Border.all(color: AppColors.textDisabled),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );

      if (i != totalSteps - 1) {
        widgets.add(
          Container(
            width: 20,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: i < currentStep ? AppColors.success : AppColors.textDisabled,
          ),
        );
      }
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: widgets);
  }
}