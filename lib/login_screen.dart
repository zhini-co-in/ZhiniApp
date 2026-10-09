import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'otp_screen.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/gestures.dart';
import 'webview_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  // Default country code - India. User can change via the picker.
  String _selectedDialCode = '+91';

  // Tracks whether the user has checked "I'm a service provider".
  bool _isServiceProfessional = false;

  // Short, inline error shown directly below the mobile number field.
  String? _errorText;

  static const Color _secondaryText = Color(0xB3FFFFFF); // white @ 70%
  static const Color _labelText = Color(0xE6FFFFFF); // white @ 90%
  static const Color _errorColor = Color(0xFFFF5A5A);
  static const String _termsUrl = 'https://atom8itsolutions.com/Zhini/term';
  static const String _privacyUrl =
      'https://atom8itsolutions.com/Zhini/privacy';

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  void _openWeb(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WebViewScreen(url: url)),
    );
  }

  // Max digits allowed for the currently selected country.
  int get _maxDigits => _selectedDialCode == '+91' ? 10 : 15;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _openWeb(_termsUrl);
    _privacyTap = TapGestureRecognizer()..onTap = () => _openWeb(_privacyUrl);
    _phoneController.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() {
    setState(() {
      // Clear any stale error as soon as the user edits the number.
      if (_errorText != null) _errorText = null;
    });
  }

  String get _digits => _phoneController.text.replaceAll(RegExp(r'\D'), '');

  /// India: exactly 10 digits starting with 6-9.
  /// Everything else: 7-15 digits (E.164 range).
  bool get _isPhoneValid {
    final d = _digits;
    if (_selectedDialCode == '+91') {
      return d.length == 10 && RegExp(r'^[6-9]').hasMatch(d);
    }
    return d.length >= 7 && d.length <= 15;
  }

  Future<void> _sendOtp() async {
    // Guard: ignore double taps while a request is already running.
    if (_isLoading) return;

    if (!_isPhoneValid) {
      setState(() => _errorText = 'Enter a valid mobile number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final fullPhoneNumber = '$_selectedDialCode$_digits';

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),

        // FIX: Do NOT sign in here. Android auto-retrieves the SMS and calls
        // this callback, which used to consume the OTP before the user typed
        // it -> "session-expired" / "OTP expired" on the OTP screen.
        // OtpScreen verifies the code manually instead.
        verificationCompleted: (PhoneAuthCredential credential) async {},

        verificationFailed: (FirebaseAuthException e) {
          debugPrint('verifyPhoneNumber failed: ${e.code} - ${e.message}');
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorText = _friendlyError(e.code);
          });
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                verificationId: verificationId,
                phoneNumber: fullPhoneNumber,
                isServiceProfessional: _isServiceProfessional,
                resendToken: resendToken,
              ),
            ),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      debugPrint('verifyPhoneNumber error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = "Couldn't send OTP. Please try again.";
      });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid mobile number. Please check and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'quota-exceeded':
        return 'Service busy. Please try again in a while.';
      default:
        return "Couldn't send OTP. Please try again.";
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Always scrollable so small phones never overflow.
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 24), // min top gap
                      const Spacer(flex: 1), // extra space on tall phones

                      Image.asset(
                        'assets/Zhini_Icon1.png',
                        width: 110,
                        height: 110,
                      ),

                      const SizedBox(height: 28), // logo -> heading

                      const Text(
                        "Your home's AI genie\nstarts here",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),

                      const SizedBox(height: 16), // heading -> subtitle

                      const Text(
                        'Enter your mobile number to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 32), // subtitle -> label

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mobile number',
                          style: TextStyle(color: _labelText, fontSize: 14),
                        ),
                      ),

                      const SizedBox(height: 8), // label -> field

                      // Phone number input row with country code picker
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 140,
                              decoration: BoxDecoration(
                                color: const Color(0xFF16243A),
                                border: Border.all(
                                  color: _errorText != null
                                      ? _errorColor
                                      : Colors.blue.shade300,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Center(
                                child: CountryCodePicker(
                                  onChanged: (country) {
                                    setState(() {
                                      _selectedDialCode =
                                          country.dialCode ?? '+91';
                                      final d = _digits;
                                      if (d.length > _maxDigits) {
                                        _phoneController.text =
                                            d.substring(0, _maxDigits);
                                        _phoneController.selection =
                                            TextSelection.collapsed(
                                                offset: _phoneController
                                                    .text.length);
                                      }
                                      _errorText = null;
                                    });
                                  },
                                  initialSelection: 'IN',
                                  favorite: const [
                                    '+91',
                                    'IN',
                                    '+1',
                                    'US',
                                    '+44',
                                    'GB'
                                  ],
                                  showCountryOnly: false,
                                  showOnlyCountryWhenClosed: false,
                                  alignLeft: false,
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(
                                      color: Colors.white, fontSize: 16),
                                  dialogTextStyle:
                                      const TextStyle(color: Colors.black),
                                  searchStyle:
                                      const TextStyle(color: Colors.black),
                                  backgroundColor: const Color(0xFF16243A),
                                  dialogBackgroundColor: Colors.white,
                                  builder: (country) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (country?.code != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: CountryFlag.fromCountryCode(
                                              country!.code!,
                                              width: 32,
                                              height: 22,
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        Text(
                                          country?.dialCode ?? '+91',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16),
                                        ),
                                        const Icon(Icons.arrow_drop_down,
                                            color: Colors.white70),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(_maxDigits),
                                ],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: 'Enter number',
                                  hintStyle:
                                      const TextStyle(color: Colors.white54),
                                  suffixIcon: _isPhoneValid
                                      ? const Icon(Icons.check_circle,
                                          color: Colors.greenAccent, size: 20)
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 16),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _errorText != null
                                          ? _errorColor
                                          : Colors.blue.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _errorText != null
                                          ? _errorColor
                                          : Colors.blue,
                                      width: 2,
                                    ),
                                  ),
                                  disabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Colors.white24),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Inline error, directly under the field, in red.
                      if (_errorText != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: _errorColor, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _errorText!,
                                  style: const TextStyle(
                                      color: _errorColor,
                                      fontSize: 13,
                                      height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14), // field -> helper text

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "We'll send a 6-digit code to verify your number.\nStandard rates may apply.",
                          style: TextStyle(
                              color: _secondaryText, fontSize: 12, height: 1.4),
                        ),
                      ),

                      const SizedBox(height: 24), // helper -> checkbox

                      // Checkbox: "I'm a service provider"
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _isServiceProfessional,
                              activeColor: Colors.blue,
                              checkColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              onChanged: (value) {
                                setState(() {
                                  _isServiceProfessional = value ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isServiceProfessional =
                                    !_isServiceProfessional;
                              });
                            },
                            child: const Text(
                              "I'm a service provider",
                              style:
                                  TextStyle(color: _labelText, fontSize: 14),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24), // checkbox -> button

                      // Send OTP button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_isLoading || !_isPhoneValid) ? null : _sendOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            disabledBackgroundColor: const Color(0xFF3A4556),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Send OTP',
                                  style: TextStyle(
                                    color: _isPhoneValid
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 18), // button -> terms

                      Text.rich(
                        TextSpan(
                          text: 'By continuing you agree to our ',
                          style: const TextStyle(
                              color: _secondaryText, fontSize: 14),
                          children: [
                            TextSpan(
                              text: 'Terms',
                              style: const TextStyle(color: Colors.blue),
                              recognizer: _termsTap,
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy policy.',
                              style: const TextStyle(color: Colors.blue),
                              recognizer: _privacyTap,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 14), // terms -> shield

                      // Divider + shield icon
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.blue.withOpacity(0.25),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: const [
                                Icon(Icons.shield_outlined,
                                    color: Colors.blue, size: 40),
                                Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.lock,
                                      color: Colors.blue, size: 16),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.blue.withOpacity(0.25),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4), // shield -> title

                      const Text(
                        'Your data & documents are protected',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 2),

                      const Text(
                        'Your information stays private and is never sold.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _secondaryText, fontSize: 13),
                      ),

                      const SizedBox(height: 20), // bottom
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}