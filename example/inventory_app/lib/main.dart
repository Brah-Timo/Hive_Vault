// example/inventory_app/lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// InventoryVault — A complete Flutter Inventory Management System
// Built with Flutter, Hive, and HiveVault.
//
// Features:
//   ✅ Onboarding — 5-step walkthrough with optional demo data
//   ✅ Barcode-based stock tracking (scan to add/remove/view)
//   ✅ Low-stock alerts with local push notifications
//   ✅ Complete CRUD for Products, Categories, Suppliers
//   ✅ Purchase Orders with receive workflow (7 status stages)
//   ✅ Stock movement history (8 movement types with audit trail)
//   ✅ Inventory Counting / Stocktake with variance reconciliation
//   ✅ Reports: Low stock, Valuation, Movements, Reorder, Summary
//   ✅ Bar & pie charts via fl_chart
//   ✅ PDF export and printing for all reports & POs
//   ✅ Auto reorder request generation grouped by supplier
//   ✅ Global search across products, suppliers, categories
//   ✅ Settings screen with notification & display preferences
//   ✅ AES-256-GCM encrypted storage via HiveVault (7 isolated vaults)
//   ✅ Offline-first — all data stored locally
//   ✅ PIN authentication with lockout protection
//   ✅ Team management with RBAC roles
//   ✅ Audit log viewer for vault operations
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/vault_service.dart';
import 'services/notification_service.dart';
import 'repositories/product_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/stock_movement_repository.dart';
import 'repositories/supplier_repository.dart';
import 'repositories/purchase_order_repository.dart';
import 'repositories/alert_repository.dart';
import 'services/stock_service.dart';
import 'services/report_service.dart';
import 'providers/inventory_provider.dart';
import 'theme/app_theme.dart' show AppTheme, themeNotifier;
import 'utils/app_routes.dart';

// ── Screens ────────────────────────────────────────────────────────────────
import 'screens/main_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/products/product_list_screen.dart';
import 'screens/products/product_form_screen.dart';
import 'screens/products/product_detail_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/suppliers/suppliers_screen.dart';
import 'screens/suppliers/supplier_detail_screen.dart';
import 'screens/stock/stock_movements_screen.dart';
import 'screens/alerts/alerts_screen.dart';
import 'screens/orders/purchase_order_list_screen.dart';
import 'screens/orders/purchase_order_form_screen.dart';
import 'screens/orders/purchase_order_detail_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/scanner/scanner_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/inventory/inventory_count_screen.dart';
import 'screens/search/global_search_screen.dart';
import 'screens/team/team_screen.dart';
import 'screens/auth/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialise HiveVault ────────────────────────────────────────────────
  final vaultService = VaultService();
  await vaultService.initialize();

  // ── Initialise notification service ────────────────────────────────────
  final notificationService = NotificationService();
  await notificationService.initialize();

  // ── Wire up repositories ──────────────────────────────────────────────
  final productRepo   = ProductRepository(vaultService.productsVault);
  final categoryRepo  = CategoryRepository(vaultService.categoriesVault);
  final movementRepo  = StockMovementRepository(vaultService.movementsVault);
  final supplierRepo  = SupplierRepository(vaultService.suppliersVault);
  final orderRepo     = PurchaseOrderRepository(vaultService.ordersVault);
  final alertRepo     = AlertRepository(vaultService.alertsVault);

  // ── Wire up services ──────────────────────────────────────────────────
  final stockService = StockService(
    productRepo:  productRepo,
    movementRepo: movementRepo,
    alertRepo:    alertRepo,
  );

  final reportService = ReportService(
    productRepo:  productRepo,
    categoryRepo: categoryRepo,
    movementRepo: movementRepo,
    orderRepo:    orderRepo,
    alertRepo:    alertRepo,
    supplierRepo: supplierRepo,
  );

  // ── Create central provider ───────────────────────────────────────────
  final inventoryProvider = InventoryProvider(
    productRepo:         productRepo,
    categoryRepo:        categoryRepo,
    movementRepo:        movementRepo,
    supplierRepo:        supplierRepo,
    orderRepo:           orderRepo,
    alertRepo:           alertRepo,
    stockService:        stockService,
    reportService:       reportService,
    notificationService: notificationService,
  );

  runApp(InventoryApp(provider: inventoryProvider));
}

class InventoryApp extends StatefulWidget {
  final InventoryProvider provider;

  const InventoryApp({super.key, required this.provider});

  @override
  State<InventoryApp> createState() => _InventoryAppState();
}

class _InventoryAppState extends State<InventoryApp> {
  /// Show onboarding on very first launch (no products / categories yet).
  bool _checkingFirstRun = true;
  bool _firstRun         = false;

  @override
  void initState() {
    super.initState();
    _detectFirstRun();
  }

  Future<void> _detectFirstRun() async {
    await widget.provider.initialize();
    final isFirst = widget.provider.allProducts.isEmpty &&
        widget.provider.categories.isEmpty;
    if (mounted) {
      setState(() {
        _firstRun          = isFirst;
        _checkingFirstRun  = false;
      });
    }
  }

  @override
  void dispose() {
    VaultService().closeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (_, themeMode, __) => MaterialApp(
        title: 'InventoryVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,

        // ── Named route table ─────────────────────────────────────────────
        // NOTE: AppRoutes.dashboard ('/') is intentionally omitted here
        // because Flutter forbids registering '/' in routes when home: is set.
        // The home: property below serves as the '/' entry point.
        routes: {
          AppRoutes.onboarding:        (_) => const OnboardingScreen(),
          AppRoutes.products:          (_) => const ProductListScreen(),
          AppRoutes.productForm:       (_) => const ProductFormScreen(),
          AppRoutes.scanner:           (_) => const ScannerScreen(),
          AppRoutes.categories:        (_) => const CategoriesScreen(),
          AppRoutes.stockMovements:    (_) => const StockMovementsScreen(),
          AppRoutes.alerts:            (_) => const AlertsScreen(),
          AppRoutes.purchaseOrders:    (_) => const PurchaseOrderListScreen(),
          AppRoutes.purchaseOrderForm: (_) => const PurchaseOrderFormScreen(),
          AppRoutes.suppliers:         (_) => const SuppliersScreen(),
          AppRoutes.reports:           (_) => const ReportsScreen(),
          AppRoutes.settings:          (_) => const SettingsScreen(),
          AppRoutes.inventoryCount:    (_) => const InventoryCountScreen(),
          AppRoutes.search:            (_) => const GlobalSearchScreen(),
          AppRoutes.team:              (_) => const TeamScreen(),
          // Parameterised routes use onGenerateRoute (see below)
        },

        // ── Parameterised / argument-based routes ─────────────────────────
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case AppRoutes.productDetail:
              final product = settings.arguments as dynamic;
              return MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
                settings: settings,
              );

            case AppRoutes.supplierDetail:
              final supplier = settings.arguments as dynamic;
              return MaterialPageRoute(
                builder: (_) => SupplierDetailScreen(supplier: supplier),
                settings: settings,
              );

            case AppRoutes.purchaseOrderDetail:
              final order = settings.arguments as dynamic;
              return MaterialPageRoute(
                builder: (_) => PurchaseOrderDetailScreen(order: order),
                settings: settings,
              );

            case AppRoutes.auth:
              return MaterialPageRoute(
                builder: (authCtx) => AuthScreen(
                  mode: AuthMode.verify,
                  onSuccess: () => Navigator.of(authCtx)
                      .pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (_) => false,
                  ),
                ),
                settings: settings,
              );

            default:
              return null; // fall through to routes table
          }
        },

        // ── Decide initial screen ─────────────────────────────────────────
        home: _checkingFirstRun
            ? const _SplashScreen()
            : _firstRun
                ? const OnboardingScreen()
                : const MainShell(),

        builder: (context, child) => child ?? const SizedBox.shrink(),
        ), // MaterialApp
      ), // ValueListenableBuilder
    );
  }
}

// ── Splash while checking first-run ─────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0x26FFFFFF), // Colors.white @ 15%
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warehouse, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'InventoryVault',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Powered by HiveVault',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'AES-256-GCM encrypted storage',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
