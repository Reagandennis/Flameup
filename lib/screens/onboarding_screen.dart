import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.local_fire_department_rounded,
      iconColor: Color(0xFFF0632A),
      title: 'Welcome to Flameup',
      description:
          'Your habit tracker that keeps the flame burning.\n'
          'Capture tasks, set due dates, and stay focused every single day.',
    ),
    _OnboardingPage(
      icon: Icons.whatshot_rounded,
      iconColor: Color(0xFFF3B447),
      title: 'Build Your Streak',
      description:
          'Complete at least one task each day to grow your streak.\n'
          'The longer the chain, the stronger the habit.',
    ),
    _OnboardingPage(
      icon: Icons.timer_outlined,
      iconColor: Color(0xFF4EAF7A),
      title: 'Focus & Flow',
      description:
          'Use the built-in 25-minute Focus timer to eliminate distractions\n'
          'and get deep work done — one task at a time.',
    ),
  ];

  Future<void> _finish() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    context.go('/home');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text('Skip',
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.5))),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (int i) => setState(() => _currentPage = i),
                itemBuilder: (BuildContext context, int index) {
                  final _OnboardingPage page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: page.iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: Icon(page.icon,
                              size: 64, color: page.iconColor),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_pages.length, (int i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? const Color(0xFFF0632A)
                        : const Color(0xFFF0632A).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast
                      ? _finish
                      : () => _pageCtrl.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF0632A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(
                    isLast ? "Let's Go!" : 'Next',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
}
