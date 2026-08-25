import 'package:flutter/material.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _pages = [
    {
      "image": "assets/images/onboard3.png",
      "title": "When Home Breaks,\nEverything Stops",
      "desc": "A broken appliance can disrupt your entire day. ZHINI helps your family stay one step ahead."
    },
    {
      "image": "assets/images/onboard2.png",
      "title": "So We Built ZHINI",
      "desc": "An AI Genie that remembers your appliances, warranties, service history, and every home care need."
    },
    {
      "image": "assets/images/onboard1.png",
      "title": "Now It's Your Turn",
      "desc": "It started with a problem in our home. We built an AI Genie to solve it. Now, every home can have one.",
    },
  ];

  void _goToNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Last page - navigate to login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Skip button - only on first/second page, bigger tap target + higher contrast
                Align(
  alignment: Alignment.topRight,
  child: Padding(
    padding: const EdgeInsets.only(top: 8.0, right: 16.0),
    child: _currentPage < _pages.length - 1
        ? TextButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => LoginScreen()),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(48, 44),
            ),
            child: const Text(
              "Skip",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : const SizedBox(height: 48),
  ),
),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Image.asset(
                                page["image"]!,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              page["title"]!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              page["desc"]!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  ),
                ),
  Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),  // 👈 horizontal padding added
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const SizedBox(width: 48),
      // Dot indicators
      Row(
        children: List.generate(_pages.length, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _currentPage == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: _currentPage == index
                  ? Colors.blue
                  : Colors.white30,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
      _currentPage == _pages.length - 1
          ? ElevatedButton(
              onPressed: _goToNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text("Get Started",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : InkWell(
              onTap: _goToNext,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
    ],
  ),
),
                // Tagline - only shown on the last page (below the button row)
                if (_currentPage == _pages.length - 1 &&
                    _pages[_currentPage]["tagline"] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _pages[_currentPage]["tagline"]!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}