import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'address_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants/api_config.dart';
import 'main_shell.dart';
import 'services/session_manager.dart';
import 'service_provider_screen.dart';
import 'service_provider_dashboard.dart';   // 👈 ADD THIS

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final bool isServiceProfessional;

  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.isServiceProfessional = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  int _secondsLeft = 60;
  Timer? _timer;
  late String _verificationId;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startTimer();
    // Rebuilds the widget whenever any box's text changes, so the
    // "Verify and continue" button can enable/disable itself in real time
    // based on whether all 6 digits are filled in.
    for (var c in _controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  void _startTimer() {
    _secondsLeft = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _maskedNumber {
    if (widget.phoneNumber.length < 6) return widget.phoneNumber;
    final visible =
        widget.phoneNumber.substring(0, widget.phoneNumber.length - 3);
    final last3 = widget.phoneNumber.substring(widget.phoneNumber.length - 3);
    return '$visible•••$last3';
  }

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  // Handles both normal single-digit typing AND a full 6-digit code pasted
  // into any one box (common on Android when the OS long-press "Paste"
  // menu is used, or when SMS autofill drops the whole code into box 0).
  void _handleDigitChange(String value, int index) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.length > 1) {
      // Pasted / autofilled full code — distribute across all boxes.
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digitsOnly.length ? digitsOnly[i] : '';
      }
      final lastFilled = (digitsOnly.length - 1).clamp(0, 5);
      _focusNodes[lastFilled].requestFocus();
      if (_enteredOtp.length == 6) _verifyOtp();
      return;
    }

    _controllers[index].text = digitsOnly;
    if (digitsOnly.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (digitsOnly.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_enteredOtp.length == 6) {
      _verifyOtp();
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _enteredOtp;
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the complete 6-digit OTP')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      await _checkExistingUserAndNavigate();
    } on FirebaseAuthException catch (e) {
      setState(() => _isVerifying = false);
      String message = 'Invalid OTP. Please try again.';
      if (e.code == 'invalid-verification-code') {
        message = 'Incorrect OTP entered.';
      } else if (e.code == 'session-expired') {
        message = 'OTP expired. Please request a new one.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      for (var c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }


Future<void> _checkExistingUserAndNavigate() async {
    // Service providers go through their own check + flow.
    if (widget.isServiceProfessional) {
      await _checkExistingProviderAndNavigate();
      return;
    }

    final plainMobile = ApiConfig.stripCountryCode(widget.phoneNumber);
    final url = '${ApiConfig.submissionSearchUrl}?mobile=$plainMobile';
    debugPrint('🔍 Checking existing user: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      debugPrint('📡 Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List homes = rawData is List ? rawData : [rawData];

          if (homes.isNotEmpty) {
            final firstHome = homes.first as Map<String, dynamic>;
            final existingHomeId = (firstHome['_id'] ?? firstHome['id'])?.toString();
            final existingAddress = (firstHome['address'] ?? '').toString();
            final rawPincode = firstHome['pincode'];
            final existingPincode = (rawPincode != null && rawPincode.toString().isNotEmpty)
                ? rawPincode.toString()
                : _extractPincode(existingAddress);

            String existingName = '';
            final membersRaw = firstHome['members'];
            if (membersRaw is List) {
              for (final m in membersRaw) {
                if (m is Map && m['mobile']?.toString() == plainMobile) {
                  existingName = m['name']?.toString() ?? '';
                  break;
                }
              }
            }

            await SessionManager.saveSession(
              mobileNumber: widget.phoneNumber,
              address: existingAddress,
              pincode: existingPincode,
              name: existingName,
              homeId: existingHomeId,
            );

            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => MainShell(
                  mobileNumber: widget.phoneNumber,
                  address: existingAddress,
                  pincode: existingPincode,
                  name: existingName,
                  homeId: existingHomeId,
                ),
              ),
            );
            return;
          }
        }
      }

      // No existing record found (or API returned success:false) — treat as
      // a new user and send them to collect their name and address.
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AddressScreen(mobileNumber: widget.phoneNumber),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error checking existing user: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  // 👇 checks if this mobile already has a service provider profile
Future<void> _checkExistingProviderAndNavigate() async {
    final plainMobile = ApiConfig.stripCountryCode(widget.phoneNumber);
    final url = ApiConfig.getServiceProviderUrl(plainMobile);
    debugPrint('🔍 Checking existing provider: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      debugPrint('📡 Provider status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List providers = data['data'] is List ? data['data'] : [data['data']];

          if (providers.isNotEmpty) {
            final firstProvider = providers.first as Map<String, dynamic>;
            final existingName = (firstProvider['name'] ?? '').toString();

            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceProviderDashboard(
                  name: existingName,
                  mobileNumber: widget.phoneNumber,
                ),
              ),
            );
            return;
          }
        }
      }

      // 404 or no data found — new provider, show the registration form.
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceProviderOnboardingScreen(
            mobileNumber: widget.phoneNumber,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error checking existing provider: $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceProviderOnboardingScreen(
            mobileNumber: widget.phoneNumber,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend: ${e.message}')),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
        });
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully')),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  String _extractPincode(String address) {
    final match = RegExp(r'\b\d{6}\b').firstMatch(address);
    return match?.group(0) ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 60),

              Image.asset(
                'assets/Zhini_Icon1.png',
                width: 80,
                height: 80,
              ),

              const SizedBox(height: 40),

              const Text(
                'Verify your number',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'We sent a 6-digit code to $_maskedNumber',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),

              const SizedBox(height: 32),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enter OTP',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      // maxLength intentionally left uncapped here so a
                      // pasted 6-digit string can land in one field and be
                      // redistributed in _handleDigitChange; each box still
                      // visually shows only its own digit once redistributed.
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        counterText: '',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.blue.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.blue, width: 2),
                        ),
                      ),
                      onChanged: (value) => _handleDigitChange(value, index),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // Resend behavior: plain disabled-looking text with the
              // countdown, becomes an active tappable link once it hits 0.
              Row(
                children: [
                  const Text("Didn't get it? ",
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                  GestureDetector(
                    onTap: _secondsLeft == 0 ? _resendOtp : null,
                    child: Text(
                      _secondsLeft == 0
                          ? 'Resend code'
                          : 'Resend code in 00:${_secondsLeft.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color:
                            _secondsLeft == 0 ? Colors.blue : Colors.white38,
                        fontSize: 13,
                        fontWeight: _secondsLeft == 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // "Verify and continue" — stays disabled (dimmed) until all
              // 6 digits are entered, and while a verification is already
              // in flight, instead of always being tappable.
              SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: (_isVerifying || _enteredOtp.length != 6) ? null : _verifyOtp,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue,
      disabledBackgroundColor: const Color(0xFF3A4556),   // 👈 theme-matching muted gray-blue
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    child: _isVerifying
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          )
        : Text(
            'Verify and continue',
            style: TextStyle(
              color: _enteredOtp.length == 6 ? Colors.white : Colors.white38,   // 👈 dim when disabled
              fontSize: 16,
            ),
          ),
  ),
),

              const SizedBox(height: 12),

              // "Change number" de-emphasized to a tertiary text action so
              // it no longer visually competes with "Verify and continue".
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Change number',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),

              const Text.rich(
                TextSpan(
                  text: 'By continuing you agree to our ',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  children: [
                    TextSpan(text: 'Terms', style: TextStyle(color: Colors.blue)),
                    TextSpan(text: ' and '),
                    TextSpan(
                        text: 'Privacy policy.',
                        style: TextStyle(color: Colors.blue)),
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
    );
  }
}