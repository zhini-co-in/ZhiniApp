import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'otp_screen.dart';

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

  // Tracks whether the user has checked "I'm a service professional".
  bool _isServiceProfessional = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the "Send OTP" button's enabled/disabled
    // state always reflects the current input (see _isPhoneValid below).
    _phoneController.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() => setState(() {});

  // Generic validation: most countries use 7-15 digit numbers (E.164 max).
  bool get _isPhoneValid {
    final digitsOnly = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 7 && digitsOnly.length <= 15;
  }

  Future<void> _sendOtp() async {
    final phoneNumber = _phoneController.text.trim();

    if (!_isPhoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid mobile number')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final fullPhoneNumber = '$_selectedDialCode$phoneNumber';

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhoneNumber,
      timeout: const Duration(seconds: 60),

      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: ${e.message}')),
        );
      },

      codeSent: (String verificationId, int? resendToken) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              verificationId: verificationId,
              phoneNumber: fullPhoneNumber,
              isServiceProfessional: _isServiceProfessional,
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        // Optional: handle timeout if needed
      },
    );
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  Image.asset(
                    'assets/Zhini_Icon1.png',
                    width: 80,
                    height: 80,
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    "Your home's AI genie\nstarts here",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'Enter your mobile number to get started.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Persistent field label (stays visible above the field,
                  // unlike a hint that disappears once typing starts).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mobile number',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Phone number input row with country code picker
                  Row(
                    children: [
                      // Country selector — explicit border + padding so it
                      // reads as clearly tappable, not just decorative text.
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Center(
                          child: CountryCodePicker(
                            onChanged: (country) {
                              setState(() {
                                _selectedDialCode = country.dialCode ?? '+91';
                              });
                            },
                            initialSelection: 'IN',
                            favorite: const ['+91', 'IN', '+1', 'US', '+44', 'GB'],
                            showCountryOnly: false,
                            showOnlyCountryWhenClosed: false,
                            alignLeft: false,
                            textStyle: const TextStyle(color: Colors.white, fontSize: 16),
                            dialogTextStyle: const TextStyle(color: Colors.black),
                            searchStyle: const TextStyle(color: Colors.black),
                            backgroundColor: const Color(0xFF0A1628),
                            dialogBackgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Enter mobile number',
                            hintStyle: const TextStyle(color: Colors.white38),
                            // Inline validation icon once a valid number is entered.
                            suffixIcon: _isPhoneValid
                                ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20)
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blue.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.blue, width: 2),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    "We'll send a 6-digit code to verify your number.\nStandard rates may apply.",
                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                  ),

                  const SizedBox(height: 24),

                  // Checkbox: "I'm a service professional"
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _isServiceProfessional,
                          activeColor: Colors.blue,
                          checkColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
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
                            _isServiceProfessional = !_isServiceProfessional;
                          });
                        },
                        child: const Text(
                          "I'm service provider",
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Send OTP button — disabled until the number is valid,
                  // loading spinner shown after tap (existing _isLoading state).
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
  onPressed: (_isLoading || !_isPhoneValid) ? null : _sendOtp,
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
          color: _isPhoneValid ? Colors.white : Colors.white38,  // 👈 dim when disabled
          fontSize: 16,
        ),
      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text.rich(
                    TextSpan(
                      text: 'By continuing you agree to our ',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                      children: [
                        TextSpan(
                          text: 'Terms',
                          style: TextStyle(color: Colors.blue),
                        ),
                        TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy policy.',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 4),

                  const Text(
                    'Your data is never sold.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}