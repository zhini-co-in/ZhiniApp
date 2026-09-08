import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'main_shell.dart';
import 'services/session_manager.dart';
import 'constants/api_config.dart';
// already add pannirukeenga (AppColors etc-ku)
import 'widgets/app_dialog_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/device_id_service.dart';
import 'dart:io'; 
import 'package:firebase_messaging/firebase_messaging.dart';

class AddressScreen extends StatefulWidget {
  final String mobileNumber;

  // true na this screen "Add Home" flow-la irundhu open aagirukku (HomeTab
  // -> Add another home). Andha mode-la:
  //   - top-right button "Skip" ku pathila "Back" (arrow) aaga maarum.
  //   - "Use current location" nera address create pannitu screen-ah
  //     pop pannidum (MainShell-ku push aagaathu).
  //   - "Register" button "Add Home" nu label maarum, adhுவும் pop
  //     pannும் (Navigator.pop) — HomeTab andha result-ah vachu backend-la
  //     home create pannும்.
  final bool isAddingHome;

  const AddressScreen({
    super.key,
    required this.mobileNumber,
    this.isAddingHome = false,
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

  // Whether all required fields have text right now — drives the
  // Register/Add Home button's enabled state so it lights up the moment
  // the form is complete, instead of staying tappable-but-erroring.
  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty &&
      _cityController.text.trim().isNotEmpty &&
      _pincodeController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Re-check validity on every keystroke across all four fields so the
    // Register/Add Home button enables itself in real time.
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

  /// Checks/requests location permission and returns the current position.
  /// Throws a plain [Exception] with a user-friendly message on failure so
  /// callers can just catch and show a SnackBar.
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

  /// Reverse-geocodes a [Position] into a best-effort "address, pincode"
  /// pair. Shared by "Use current location" (autofill), "Add Home" (one-tap
  /// add) and "Skip" (default-home-from-GPS) so all three resolve GPS the
  /// same way instead of drifting apart.
  ///
  /// Never throws — if geocoding fails or returns nothing usable, falls
  /// back to a raw "Lat X, Lng Y" string so callers always have SOME
  /// address to create a home with.
  Future<({String address, String city, String pincode})> _resolveAddressFromPosition(
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

    // Fallback — raw coordinates, so there's always something to work with.
    final fallback =
        'Lat ${position.latitude.toStringAsFixed(4)}, Lng ${position.longitude.toStringAsFixed(4)}';
    return (address: fallback, city: '', pincode: '');
  }

  /// "Use current location" — fetches GPS position, reverse-geocodes it,
  /// and autofills the address / city / pincode fields so the user can
  /// just review + edit instead of typing everything manually.
  ///
  /// Used in the NORMAL (signup) flow only. In "Add Home" mode we skip the
  /// autofill-and-review step and go straight to
  /// [_useCurrentLocationAndAddHome] instead — see that method below.
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
        const SnackBar(content: Text('Address filled from current location. Please review.')),
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

  /// "Add Home" flow ONLY — fetches GPS, reverse-geocodes it, and pops
  /// straight back to HomeTab with the resolved address instead of just
  /// autofilling the form. Lets the user add a home with ONE tap using
  /// their current location, without also having to press "Add Home"
  /// afterwards.
/// "Add Home" flow-லும் — GPS fetch பண்ணி, reverse-geocode பண்ணி, form
/// fields-ஐ autofill பண்ணும் (like normal signup flow). User "Add Home"
/// button explicit-ah press pண்ணும்போது மட்டும் தான் home create ஆகும்.
Future<void> _useCurrentLocationAndAddHome() async {
  setState(() => _isFetchingLocation = true);
  try {
    final position = await _determinePosition();
    final resolved = await _resolveAddressFromPosition(position);

    _addressController.text = resolved.address;
    _cityController.text = resolved.city;
    _pincodeController.text = resolved.pincode;
    // Add Home mode-ல name field கேட்கலைனா, fallback name kudுங்க
    if (_nameController.text.trim().isEmpty) {
      _nameController.text = 'Guest';
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address filled from current location. Review and tap Add Home.')),
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

    // "Add Home" flow — don't touch the signup session, don't create the
    // home ourselves, and don't push MainShell. Just hand the new
    // address/pincode back to HomeTab (which called us via
    // Navigator.push<Map>) so IT can create the home and refresh its list.
    if (widget.isAddingHome) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context, {'address': fullAddress, 'pincode': pincode});
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
  // SKIP — no address typed in. Grabs lat/long (location already being
  // tracked elsewhere in the app, so permission is most likely already
  // granted), reverse-geocodes it into a best-effort address, and creates
  // a REAL default home from that — same as the "Register" flow, just
  // auto-filled from GPS instead of typed by hand.
  //
  // This is the key fix: previously Skip only saved an empty session and
  // pushed MainShell with homeId: null, which meant no home was ever
  // created and the user always landed on the "Set up your home" prompt
  // screen instead of their actual home. Now Skip lands them on the same
  // real home screen Register does — the button/design stays identical,
  // only what happens behind it changes.
  //
  // Only used in the normal (signup) flow — "Add Home" mode shows a
  // "Back" button instead of "Skip" (see build()).
  // ---------------------------------------------------------------------

Future<void> _skip() async {
  setState(() => _isSkipping = true);
  try {
    // Location permission மட்டும் confirm பண்றோம் — GPS ஒண்ணும்
    // use பண்ணல, "Default" address-க்கு backend-ல ஒரு real home
    // create பண்றோம் இப்போ, so scan pannitu register panna அதே
    // home update ஆகும் (see HomeTab._isDefaultHome / _defaultHome).
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

    // 👈 NEW — backend-ல "Default" address-oda real home create pannunga.
    // HomeTab andha home-a isDefault-nu recognize pannum (address == 'Default'),
    // so Register card continue-a காட்டும், ஆனா devices already andha
    // homeId-ku கீழ சேமிக்கப்படும்.
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
          homeId: defaultHomeId,   // 👈 null இல்ல, ippo real homeId varum
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
  // BACKEND — calls the proper /createHome endpoint (upserts the user +
  // creates/reuses a home for this address). Used by Register AND Skip.
  // ---------------------------------------------------------------------

Future<String?> _createNewHomeRecord({
  required String address,
  required String pincode,
  required String name,
}) async {
  try {
    final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    final deviceId = await DeviceIdService.getDeviceId();
    final fcmToken = await FirebaseMessaging.instance.getToken();

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
                    widget.isAddingHome ? "Let's add a new home" : "Let's set up your home",
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

                  // Manual entry fields — filled in directly, or pre-filled
                  // by "Use current location" below.
                  AppDialogField(controller: _nameController, hint: 'Your name'),
                  const SizedBox(height: 16),
                  AppDialogField(controller: _addressController, hint: 'House / Street / Area'),
                  const SizedBox(height: 16),
                  AppDialogField(controller: _cityController, hint: 'City'),
                  const SizedBox(height: 16),
                  AppDialogField(
                    controller: _pincodeController,
                    hint: 'Pincode',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),

                  // Clear divider between "type it in yourself" and "use
                  // GPS" — shown for BOTH the normal signup flow and the
                  // "Add Home" flow, so it's never ambiguous which path
                  // the user is on.
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

                  // "Use current location" — autofills the fields above in
                  // the normal signup flow. In "Add Home" mode, this
                  // instead completes the add-home flow immediately (no
                  // need to also fill the form / press Add Home).
                  Align(
  alignment: Alignment.center,
  child: TextButton.icon(
    onPressed: (_isFetchingLocation || anyActionInProgress)
        ? null
        : _useCurrentLocationForAddress,   // 👈 rendு modes-லும் இதே function
    icon: _isFetchingLocation
        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.my_location, size: 18, color: Colors.blue),
    label: Text(
      widget.isAddingHome ? 'Use current location' : 'Use current location',
      style: const TextStyle(color: Colors.blue),
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
      disabledBackgroundColor: const Color(0xFF3A4556),   // 👈 theme-matching muted gray-blue
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
              color: _isFormValid ? Colors.white : Colors.white38,   // 👈 dim when disabled
              fontSize: 16,
            ),
          ),
  ),
),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // "Add Home" flow — Back button on the LEFT (standard nav
            // position, since there's nothing meaningful to "skip" here).
            if (widget.isAddingHome)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: anyActionInProgress
                      ? null
                      : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white60),
                  tooltip: 'Back',
                ),
              )
            // Normal signup flow — "Skip" stays on the RIGHT, jumps
            // straight in using GPS lat/long only.
            else
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
                          style: TextStyle(color: Colors.white60, fontSize: 15),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}