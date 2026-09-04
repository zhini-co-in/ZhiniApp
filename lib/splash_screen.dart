import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'onboarding_screen.dart';
import 'main_shell.dart';
import 'services/session_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });

    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final session = await SessionManager.getSession();

    if (session != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainShell(
            mobileNumber: session['mobileNumber']!,
            address: session['address']!,
            pincode: session['pincode']!,
            name: session['name'] ?? '',
            homeId: session['homeId']?.isNotEmpty == true
                ? session['homeId']
                : null,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  // ---- Opens the device's mail app with support@zhini.co.in pre-filled ----
  Future<void> _openSupportMail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@zhini.co.in',
      query: 'subject=ZHINI App Support',
    );
    try {
      await launchUrl(emailUri);
    } catch (e) {
      debugPrint('Email launch error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/Zhini_Icon1.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 0),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'ZHINI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 7.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: InkWell(
                onTap: _openSupportMail,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  child: Text(
                    'Powered by Atom8',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}