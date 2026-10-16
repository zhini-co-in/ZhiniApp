import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_shell.dart';
import 'service_provider_screen.dart';
import 'services/session_manager.dart';
import 'services/device_id_service.dart';
import 'services/api_client.dart';
import 'constants/api_config.dart';
import 'widgets/app_dialog_field.dart';

class AddressScreen extends StatefulWidget {
  final String mobileNumber;

  // true na this screen "Add Home" flow-la irundhu open aagirukku (HomeTab
  // -> Add another home). Andha mode-la:
  //   - top-right "Skip" ku pathila "Back" arrow varum.
  //   - "Register" button "Add Home" nu maarum, Navigator.pop pannum.
  final bool isAddingHome;

  // true na user "I'm a service provider" tick pannirukkaanga. User (home)
  // create aana piragu MainShell ku badhula Provider onboarding ku poganum.
  final bool isServiceProfessional;

  const AddressScreen({
    super.key,
    required this.mobileNumber,
    this.isAddingHome = false,
    this.isServiceProfessional = false,
  });

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  bool _isSaving = false; // save & continue in progress
  bool _isSkipping = false; // skip-with-location in progress
  bool _isFetchingLocation = false; // "use current location" autofill in progress

  // Drives the Register/Add Home button's enabled state.
  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty &&
      _cityController.text.trim().isNotEmpty &&
      _pincodeController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameController,
      _addressController,
      _cityController,
      _pincodeController,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------
  // LOCATION HELPERS
  // ---------------------------------------------------------------------

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Please turn on location services to continue.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied. Enable it from app settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Reverse-geocodes a [Position] into address / city / pincode.
  /// Never throws — falls back to raw "Lat X, Lng Y".
  Future<({String address, String city, String pincode})>
      _resolveAddressFromPosition(
    Position position,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final streetBits = [
          place.name,
          place.street,
          place.subLocality,
        ].where((e) => e != null && e.isNotEmpty).toSet().join(', ');
        final city = place.locality ?? place.subAdministrativeArea ?? '';
        final pincode = place.postalCode ?? '';

        if (streetBits.isNotEmpty || city.isNotEmpty) {
          return (address: streetBits, city: city, pincode: pincode);
        }
      }
    } catch (e) {
      debugPrint('❌ Reverse geocode error: $e');
    }

    final fallback =
        'Lat ${position.latitude.toStringAsFixed(4)}, Lng ${position.longitude.toStringAsFixed(4)}';
    return (address: fallback, city: '', pincode: '');
  }

  /// "Use current location" — autofills address / city / pincode.
  Future<void> _useCurrentLocationForAddress() async {
    setState(() => _isFetchingLocation = true);
    try {
      final position = await _determinePosition();
      final resolved = await _resolveAddressFromPosition(position);

      _addressController.text = resolved.address;
      _cityController.text = resolved.city;
      _pincodeController.text = resolved.pincode;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Address filled from current location. Please review.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  // ---------------------------------------------------------------------
  // SAVE (full manual/auto-filled address form)
  // ---------------------------------------------------------------------

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();

    if (name.isEmpty || address.isEmpty || city.isEmpty || pincode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final fullAddress = '$address, $city - $pincode';

    // "Add Home" flow — hand the new address back to HomeTab.
    if (widget.isAddingHome) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(
          context, {'address': fullAddress, 'pincode': pincode, 'name': name});
      return;
    }

    await SessionManager.saveSession(
      mobileNumber: widget.mobileNumber,
      address: fullAddress,
      pincode: pincode,
      name: name,
    );

    final newHomeId = await _createNewHomeRecord(
      address: fullAddress,
      pincode: pincode,
      name: name,
    );

    if (!mounted) return;

    // Service provider flow: user MUST be created first. If it failed,
    // stop here (otherwise provider create will 401).
    if (widget.isServiceProfessional) {
      if (newHomeId == null) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not create your account. Please try again.')),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceProviderOnboardingScreen(
            mobileNumber: widget.mobileNumber,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainShell(
          mobileNumber: widget.mobileNumber,
          address: fullAddress,
          pincode: pincode,
          name: name,
          homeId: newHomeId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SKIP — creates a "Default" home from GPS permission check.
  // (Hidden when the user ticked "service provider", see build().)
  // ---------------------------------------------------------------------

  Future<void> _skip() async {
    setState(() => _isSkipping = true);
    try {
      await _determinePosition();

      const defaultAddress = 'Default';
      const defaultPincode = '';
      const defaultName = 'Guest';

      await SessionManager.saveSession(
        mobileNumber: widget.mobileNumber,
        address: defaultAddress,
        pincode: defaultPincode,
        name: defaultName,
      );

      final defaultHomeId = await _createNewHomeRecord(
        address: defaultAddress,
        pincode: defaultPincode,
        name: defaultName,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainShell(
            mobileNumber: widget.mobileNumber,
            address: defaultAddress,
            pincode: defaultPincode,
            name: defaultName,
            homeId: defaultHomeId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  // ---------------------------------------------------------------------
  // BACKEND — calls /createHome (upserts the user + creates/reuses a home).
  // This is what saves the user + authToken on the backend.
  // ---------------------------------------------------------------------

  Future<String?> _createNewHomeRecord({
    required String address,
    required String pincode,
    required String name,
  }) async {
    try {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final deviceId = await DeviceIdService.getDeviceId();
      final fcmToken = await ApiClient.safeFcmToken();

      if (authToken == null) {
        debugPrint('❌ No Firebase auth token — user not signed in?');
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
          'PlatformInfo': {
            'device': {
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'os': Platform.isAndroid ? 'android' : 'ios',
            },
          },
        }),
      );

      debugPrint('🏠 Create new home status: ${response.statusCode}');
      debugPrint('🏠 Create new home body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['homeId']?.toString();
        }
      }
    } catch (e) {
      debugPrint('❌ Create new home error: $e');
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _addressController,
      _cityController,
      _pincodeController,
    ]) {
      c.removeListener(_onFieldChanged);
    }
    _nameController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool anyActionInProgress = _isSaving || _isSkipping;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Image.asset('assets/Zhini_Icon1.png', width: 80, height: 80),
                  const SizedBox(height: 40),
                  Text(
                    widget.isAddingHome
                        ? "Let's add a new home"
                        : "Let's set up your home",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isAddingHome
                        ? 'Use your current location for a one-tap add, or enter the address manually below.'
                        : 'ZHINI uses this to personalize your experience and connect you with nearby service.',
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  AppDialogField(
                      controller: _nameController, hint: 'Your name'),
                  const SizedBox(height: 16),
                  AppDialogField(
                      controller: _addressController,
                      hint: 'House / Street / Area'),
                  const SizedBox(height: 16),
                  AppDialogField(controller: _cityController, hint: 'City'),
                  const SizedBox(height: 16),
                  AppDialogField(
                    controller: _pincodeController,
                    hint: 'Pincode',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),

                  const SizedBox(height: 20),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: (_isFetchingLocation || anyActionInProgress)
                          ? null
                          : _useCurrentLocationForAddress,
                      icon: _isFetchingLocation
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location,
                              size: 18, color: Colors.blue),
                      label: const Text(
                        'Use current location',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (anyActionInProgress || !_isFormValid)
                          ? null
                          : _saveAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: const Color(0xFF3A4556),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              widget.isAddingHome ? 'Add Home' : 'Register',
                              style: TextStyle(
                                color: _isFormValid
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // "Add Home" flow — Back button on the LEFT.
            if (widget.isAddingHome)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: anyActionInProgress
                      ? null
                      : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white60),
                  tooltip: 'Back',
                ),
              )
            // Normal signup flow — "Skip" on the RIGHT. Hidden for service
            // providers (they must create a real user first).
            else if (!widget.isServiceProfessional)
              Positioned(
                top: 8,
                right: 8,
                child: TextButton(
                  onPressed: anyActionInProgress ? null : _skip,
                  child: _isSkipping
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white60,
                          ),
                        )
                      : const Text(
                          'Skip',
                          style:
                              TextStyle(color: Colors.white60, fontSize: 15),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}