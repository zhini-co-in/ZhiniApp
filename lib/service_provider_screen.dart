import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'constants/api_config.dart';
import 'service_provider_dashboard.dart';
import 'login_screen.dart';

class ServiceProviderOnboardingScreen extends StatefulWidget {
  final String mobileNumber;

  const ServiceProviderOnboardingScreen({
    super.key,
    required this.mobileNumber,
  });

  @override
  State<ServiceProviderOnboardingScreen> createState() =>
      _ServiceProviderOnboardingScreenState();
}

class _ServiceProviderOnboardingScreenState
    extends State<ServiceProviderOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0 = step1, 1 = step2, 2 = step3
  static const int _totalSteps = 3;

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
    'Carpenter',
    'Painting',
    'Others',
  ];
  final Set<String> _selectedAppliances = {};

  double _workingRangeKm = 1;
  bool _isSubmitting = false;

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
  _pincodeController.dispose();   // ✅
  _gstinController.dispose();
  _othersController.dispose();
  super.dispose();
}

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        title: const Text('Log out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will need to verify your mobile number again.',
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: Colors.blue)),
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

  void _onContinueFromStep2() {
    _goToStep(2);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- Submit ----------------

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final finalExpertise =
          _selectedAppliances.where((e) => e != 'Others').toList();
      if (_selectedAppliances.contains('Others')) {
        final customServices = _othersController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);
        finalExpertise.addAll(customServices);
      }

      final uri = Uri.parse(ApiConfig.createServiceProviderUrl);
      final request = http.MultipartRequest('POST', uri)
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..fields['name'] = _nameController.text.trim()
        ..fields['mobile'] = _plainMobile
        ..fields['address'] = _addressController.text.trim()
        ..fields['pincode'] = _pincodeController.text.trim()
        ..fields['range'] = _workingRangeKm.round().toString()
        ..fields['expertise'] = finalExpertise.join(',');

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
        backgroundColor: const Color(0xFF0A1628),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A1628),
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: _currentStep == 0
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => _goToStep(_currentStep - 1),
                ),
          title: const Text(
            'Become a service provider',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70),
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
                      _buildStep3(),
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

  // ---- Step 1: Your profile ----
  Widget _buildStep1() {
    return _StepCard(
      title: 'Your profile',
      stepLabel: 'Step 1 of $_totalSteps',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Full name'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: _fieldDecoration('Enter your full name'),
            ),
            const SizedBox(height: 20),
            _label('City / service area'),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: _fieldDecoration('e.g. Chennai — T. Nagar, Adyar'),
            ),
            const SizedBox(height: 20),
_label('Pincode'),
const SizedBox(height: 8),
TextField(
  controller: _pincodeController,
  keyboardType: TextInputType.number,
  maxLength: 6,
  style: const TextStyle(color: Colors.white, fontSize: 16),
  decoration: _fieldDecoration('e.g. 600045').copyWith(
    counterText: '', // hides the 0/6 counter
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
                return FilterChip(
                  label: Text(appliance),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedAppliances.add(appliance);
                      } else {
                        _selectedAppliances.remove(appliance);
                      }
                    });
                  },
                  showCheckmark: false,
                  surfaceTintColor: Colors.transparent,
                  selectedColor: Colors.blue,
                  backgroundColor: const Color(0xFF13253F),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? Colors.blue : Colors.blue.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
            if (_selectedAppliances.contains('Others')) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _othersController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: _fieldDecoration(
                    'e.g. Pest control, Home cleaning (comma separated)'),
              ),
            ],
            const SizedBox(height: 28),
            _primaryButton('Continue', onPressed: _onContinueFromStep1),
          ],
        ),
      ),
    );
  }

  // ---- Step 2: Store details ----
  Widget _buildStep2() {
    return _StepCard(
      title: 'Store details',
      stepLabel: 'Step 2 of $_totalSteps',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Store photo'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickStorePhoto,
              child: Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300),
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: _storePhoto == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, color: Colors.blue, size: 26),
                          SizedBox(height: 4),
                          Text('Add photo',
                              style: TextStyle(color: Colors.white60, fontSize: 11)),
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
                style: const TextStyle(
                    color: Colors.blue, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            Slider(
              value: _workingRangeKm,
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: Colors.blue,
              inactiveColor: Colors.white24,
              label: '${_workingRangeKm.round()} km',
              onChanged: (value) => setState(() => _workingRangeKm = value),
            ),
            const SizedBox(height: 12),
            _label('GSTIN (optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _gstinController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: _fieldDecoration('e.g. 22AAAAA0000A1Z5'),
            ),
            const SizedBox(height: 28),
            _primaryButton('Continue', onPressed: _onContinueFromStep2),
          ],
        ),
      ),
    );
  }

  // ---- Step 3: Free CRM activated ----
  Widget _buildStep3() {
    return _StepCard(
      title: 'Free CRM activated',
      stepLabel: 'Step 3 of $_totalSteps',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'ZHINI CRM is free',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Job management · Invoice generation · Customer history',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF13253F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Your referral code',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _referralCode,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Earn ₹200 when a colleague joins and completes first job',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
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
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      );

  Widget _primaryButton(String text,
      {required VoidCallback? onPressed, bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          disabledBackgroundColor: Colors.blue.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
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
        color: const Color(0xFF0F2038),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stepLabel,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The small dot + connecting-line progress indicator at the top,
/// matching the reference screenshot: completed = green, current =
/// elongated blue pill, upcoming = grey outline.
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
                ? Colors.greenAccent
                : (isCurrent ? Colors.blue : Colors.transparent),
            border: isCurrent || isCompleted
                ? null
                : Border.all(color: Colors.white24),
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
            color: i < currentStep ? Colors.greenAccent : Colors.white24,
          ),
        );
      }
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: widgets);
  }
}