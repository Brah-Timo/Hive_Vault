// example/inventory_app/lib/screens/onboarding/onboarding_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// 5-step animated onboarding walkthrough with optional demo-data seed.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../theme/app_theme.dart';
import '../main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  bool _loadingDemo = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _pages = [
    _OnboardingData(
      icon: Icons.warehouse_rounded,
      color: Color(0xFF1565C0),
      gradientEnd: Color(0xFF1E88E5),
      title: 'Welcome to InventoryVault',
      body:
          'A complete offline-first inventory management system. '
          'All data stays on your device, encrypted with AES-256-GCM.',
      feature1: '🔒 Bank-grade encryption',
      feature2: '📱 100% offline-first',
      feature3: '⚡ Lightning fast storage',
    ),
    _OnboardingData(
      icon: Icons.qr_code_scanner_rounded,
      color: Color(0xFF00897B),
      gradientEnd: Color(0xFF00ACC1),
      title: 'Barcode-Based Tracking',
      body:
          'Scan EAN-13, UPC-A, QR codes, or enter barcodes manually to '
          'look up products, record stock movements, and run counts.',
      feature1: '📸 Camera barcode scanning',
      feature2: '✏️ Manual barcode entry',
      feature3: '📦 8 movement types',
    ),
    _OnboardingData(
      icon: Icons.notifications_active_rounded,
      color: Color(0xFFF57C00),
      gradientEnd: Color(0xFFFFB300),
      title: 'Smart Alerts',
      body:
          'Automatic low-stock, out-of-stock, and reorder notifications. '
          'Set custom thresholds per product and get notified instantly.',
      feature1: '🔔 Push notifications',
      feature2: '📉 Low-stock alerts',
      feature3: '🔄 Auto reorder requests',
    ),
    _OnboardingData(
      icon: Icons.bar_chart_rounded,
      color: Color(0xFF6A1B9A),
      gradientEnd: Color(0xFF8E24AA),
      title: 'Reports & Analytics',
      body:
          'Low-stock, valuation, movement history, and reorder reports '
          'with interactive charts. Export to PDF and share instantly.',
      feature1: '📊 Interactive charts',
      feature2: '📄 PDF export',
      feature3: '📈 5 report types',
    ),
    _OnboardingData(
      icon: Icons.shopping_cart_rounded,
      color: Color(0xFF388E3C),
      gradientEnd: Color(0xFF43A047),
      title: 'Purchase Orders',
      body:
          'Create and manage purchase orders with a 7-stage workflow. '
          'Receive goods, track partial deliveries, and auto-update stock.',
      feature1: '📋 7 order statuses',
      feature2: '🚚 Receive workflow',
      feature3: '🏪 Supplier management',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _fadeController.reverse().then((_) {
        _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        _fadeController.forward();
      });
    }
  }

  void _skip() => _enterApp(loadDemo: false);

  Future<void> _enterApp({required bool loadDemo}) async {
    if (_loadingDemo) return;
    final prov = context.read<InventoryProvider>();

    if (loadDemo) {
      setState(() => _loadingDemo = true);
      await prov.seedDemoData();
      if (!mounted) return;
      setState(() => _loadingDemo = false);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const MainShell(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [page.color, page.gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                  child: TextButton(
                    onPressed: _skip,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) {
                    setState(() => _currentPage = i);
                    _fadeController.reset();
                    _fadeController.forward();
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, i) =>
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: _pages[i].build(context, size),
                      ),
                ),
              ),

              // Bottom area: dots + button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  children: [
                    // Page indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 24),

                    if (isLast) ...[
                      // Final page: two buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loadingDemo
                              ? null
                              : () => _enterApp(loadDemo: true),
                          icon: _loadingDemo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primaryColor))
                              : const Icon(Icons.dataset_rounded),
                          label: Text(_loadingDemo
                              ? 'Loading demo data…'
                              : 'Load Demo Data & Start'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: page.color,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadingDemo
                              ? null
                              : () => _enterApp(loadDemo: false),
                          icon: const Icon(
                              Icons.play_arrow_rounded),
                          label: const Text('Start Fresh (Empty)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side:
                                const BorderSide(color: Colors.white60),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Next button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: page.color,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: const [
                              Text('Next'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data model for a single onboarding page.
class _OnboardingData {
  final IconData icon;
  final Color color;
  final Color gradientEnd;
  final String title;
  final String body;
  final String feature1;
  final String feature2;
  final String feature3;

  const _OnboardingData({
    required this.icon,
    required this.color,
    required this.gradientEnd,
    required this.title,
    required this.body,
    required this.feature1,
    required this.feature2,
    required this.feature3,
  });

  Widget build(BuildContext context, Size size) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),

          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Body
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.85),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Feature chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [feature1, feature2, feature3].map((f) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  f,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
