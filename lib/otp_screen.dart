import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'address_screen.dart';
import 'constants/api_config.dart';
import 'main_shell.dart';
import 'services/session_manager.dart';
import 'service_provider_screen.dart';
import 'service_provider_dashboard.dart';
import 'login_screen.dart';
import 'services/log_service.dart';
import 'services/api_client.dart';
// Phase 3:
// import 'services/push_service.dart';

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final bool isServiceProfessional;
  final int? resendToken; // NEW: passed from login screen

  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.isServiceProfessional = false,
    this.resendToken,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _otpLength = 6;

  // One hidden TextField holds the whole code. The 6 boxes only display it.
  // This makes paste, autofill and backspace work reliably on every device.
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsLeft = 60;
  Timer? _timer;
  late String _verificationId;
  int? _resendToken;

  // Short inline error shown directly below the OTP boxes.
  String? _otpError;

  static const Color _secondaryText = Color(0xB3FFFFFF); // white @ 70%
  static const Color _labelText = Color(0xE6FFFFFF); // white @ 90%
  static const Color _errorColor = Color(0xFFFF5A5A);

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _startTimer();
    _otpController.addListener(() {
      if (mounted) setState(() {});
    });
    _otpFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _otpFocus.requestFocus();
    });
  }

  void _startTimer() {
    _secondsLeft = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  /// Renders as "+91 98••••••12"
  String get _maskedNumber {
    final raw = widget.phoneNumber.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return raw;

    final localLen = digits.length > 10 ? 10 : digits.length;
    final countryCode = digits.substring(0, digits.length - localLen);
    final local = digits.substring(digits.length - localLen);

    final first2 = local.substring(0, 2);
    final last2 = local.substring(local.length - 2);
    final masked = '•' * (local.length - 4);

    final prefix = countryCode.isNotEmpty ? '+$countryCode ' : '';
    return '$prefix$first2$masked$last2';
  }

  String get _enteredOtp => _otpController.text;

  // Called on every typing / paste / backspace in the hidden field.
  void _handleOtpChanged(String value) {
    if (_otpError != null) {
      setState(() => _otpError = null);
    }
    if (value.length == _otpLength) {
      _verifyOtp();
    }
  }

  // "Paste" button — reads the clipboard and fills all 6 boxes.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    final code =
        digits.length > _otpLength ? digits.substring(0, _otpLength) : digits;
    _otpController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    if (_otpError != null) setState(() => _otpError = null);
    _otpFocus.requestFocus();
    if (code.length == _otpLength) _verifyOtp();
  }

  void _clearOtp() {
    _otpController.clear();
    _otpFocus.requestFocus();
  }

  Future<void> _verifyOtp() async {
    // Block duplicate calls (autofill / paste / button tap can trigger
    // this twice; the 2nd call would fail with session-expired).
    if (_isVerifying) return;

    final otp = _enteredOtp;
    if (otp.length != _otpLength) {
      setState(() => _otpError = 'Enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _otpError = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      _onSignedIn();

      if (!mounted) return;
      await _checkExistingUserAndNavigate();
    } on FirebaseAuthException catch (e) {
      debugPrint('OTP error: ${e.code} - ${e.message}');
      if (!mounted) return;

      // Safety net: if the user is already signed in with this number
      // (e.g. auto-retrieval finished first), just continue.
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && current.phoneNumber == widget.phoneNumber) {
        _onSignedIn();
        await _checkExistingUserAndNavigate();
        return;
      }

      String message = "Couldn't verify the code. Try again.";
      if (e.code == 'invalid-verification-code') {
        message = 'Incorrect OTP. Try again.';
      } else if (e.code == 'session-expired') {
        message = 'OTP expired. Request a new one.';
      } else if (e.code == 'network-request-failed') {
        message = 'No internet connection. Please try again.';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      }

      setState(() {
        _isVerifying = false;
        _otpError = message;
      });
      _clearOtp();
    } catch (e) {
      debugPrint('Unexpected OTP error: $e');
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _otpError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _onSignedIn() {
    LogService.instance.mobile = widget.phoneNumber;
    ApiClient.mobile = widget.phoneNumber;
    FirebaseCrashlytics.instance
        .setUserIdentifier(widget.phoneNumber.hashCode.toString());
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
      final response = await ApiClient.get(url);
      debugPrint('📡 Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List homes = rawData is List ? rawData : [rawData];

          if (homes.isNotEmpty) {
            final firstHome = homes.first as Map<String, dynamic>;
            final existingHomeId =
                (firstHome['_id'] ?? firstHome['id'])?.toString();
            final existingAddress = (firstHome['address'] ?? '').toString();
            final rawPincode = firstHome['pincode'];
            final existingPincode =
                (rawPincode != null && rawPincode.toString().isNotEmpty)
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

      // No existing record found — treat as a new user.
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
      setState(() => _otpError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  // Checks if this mobile already has a service provider profile.
  Future<void> _checkExistingProviderAndNavigate() async {
    final plainMobile = ApiConfig.stripCountryCode(widget.phoneNumber);
    final url = ApiConfig.getServiceProviderUrl(plainMobile);
    debugPrint('🔍 Checking existing provider: $url');

    try {
      final response = await ApiClient.get(url);
      debugPrint(
          '📡 Provider status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List providers =
              data['data'] is List ? data['data'] : [data['data']];

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
    if (_isResending) return;
    setState(() {
      _isResending = true;
      _otpError = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,

        // No auto sign-in here either, otherwise the OTP is consumed.
        verificationCompleted: (PhoneAuthCredential credential) async {},

        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Resend failed: ${e.code} - ${e.message}');
          if (!mounted) return;
          setState(() {
            _isResending = false;
            _otpError = "Couldn't resend the code. Try again.";
          });
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isResending = false;
            _otpError = null;
          });
          _clearOtp();
          _startTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP resent')),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      debugPrint('Resend error: $e');
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _otpError = "Couldn't resend the code. Try again.";
      });
    }
  }

  // Push a fresh login screen (Navigator.pop would leave a black screen
  // because the login route was replaced).
  void _changeNumber() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _extractPincode(String address) {
    final match = RegExp(r'\b\d{6}\b').firstMatch(address);
    return match?.group(0) ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  // The 6 visual boxes + the invisible TextField laid on top of them.
  Widget _buildOtpBoxes() {
    final text = _otpController.text;
    final focused = _otpFocus.hasFocus;
    final activeIndex = text.length.clamp(0, _otpLength - 1);

    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          // Visual boxes
          Row(
            children: [
              for (int i = 0; i < _otpLength; i++) ...[
                Expanded(
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _otpError != null
                            ? _errorColor
                            : (focused && i == activeIndex)
                                ? Colors.blue
                                : Colors.blue.shade300,
                        width: (focused && i == activeIndex) ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (i != _otpLength - 1) const SizedBox(width: 8),
              ],
            ],
          ),

          // Invisible input on top: receives typing, paste (long-press),
          // autofill and backspace.
          Positioned.fill(
            child: TextField(
              controller: _otpController,
              focusNode: _otpFocus,
              enabled: !_isVerifying,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: _otpLength,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_otpLength),
              ],
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _handleOtpChanged,
            ),
          ),
        ],
      ),
    );
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
                width: 112,
                height: 112,
              ),

              const SizedBox(height: 40),

              const Text(
                'Verify your number',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Column(
                children: [
                  const Text(
                    'We sent a 6-digit code to',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _secondaryText, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _maskedNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Enter OTP',
                    style: TextStyle(color: _labelText, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: _isVerifying ? null : _pasteFromClipboard,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.content_paste_rounded,
                            size: 14, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'Paste',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _buildOtpBoxes(),

              // Inline error, right under the boxes, in red.
              if (_otpError != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: _errorColor, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _otpError!,
                        style: const TextStyle(
                            color: _errorColor, fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              Align(
                alignment: Alignment.centerLeft,
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in 00:${_secondsLeft.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: _secondaryText, fontSize: 13),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Didn't get the code? ",
                            style: TextStyle(
                                color: _secondaryText, fontSize: 13),
                          ),
                          GestureDetector(
                            onTap: _isResending ? null : _resendOtp,
                            child: Text(
                              _isResending ? 'Sending...' : 'Resend',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 32),

              // "Verify and continue"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isVerifying || _enteredOtp.length != _otpLength)
                      ? null
                      : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: const Color(0xFF3A4556),
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
                            color: _enteredOtp.length == _otpLength
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _isVerifying ? null : _changeNumber,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Change number',
                  style: TextStyle(color: _labelText, fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),

              const Text.rich(
                TextSpan(
                  text: 'By continuing you agree to our ',
                  style: TextStyle(color: _secondaryText, fontSize: 12),
                  children: [
                    TextSpan(
                        text: 'Terms', style: TextStyle(color: Colors.blue)),
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
                'Your data will never be sold.',
                style: TextStyle(color: _secondaryText, fontSize: 12),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}