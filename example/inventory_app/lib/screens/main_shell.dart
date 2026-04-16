// example/inventory_app/lib/screens/main_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// Bottom navigation shell + side drawer + centre scanner FAB.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import 'dashboard/dashboard_screen.dart';
import 'products/product_list_screen.dart';
import 'alerts/alerts_screen.dart';
import 'orders/purchase_order_list_screen.dart';
import 'reports/reports_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _screens = [
    DashboardScreen(),
    ProductListScreen(),
    AlertsScreen(),
    PurchaseOrderListScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          // Centre scanner FAB between nav bar items
          floatingActionButton: FloatingActionButton(
            heroTag: 'shellScanFab',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.scanner),
            tooltip: 'Scan Barcode',
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 4,
            child: const Icon(Icons.qr_code_scanner),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: BottomAppBar(
            shape: const CircularNotchedRectangle(),
            notchMargin: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Dashboard
                _navItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Home',
                  index: 0,
                ),
                // Products
                _navItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  label: 'Products',
                  index: 1,
                ),
                // Spacer for FAB
                const SizedBox(width: 56),
                // Alerts with badge
                _navItemWithBadge(
                  icon: Icons.notifications_outlined,
                  activeIcon: Icons.notifications,
                  label: 'Alerts',
                  index: 2,
                  badgeCount: prov.unreadAlertCount,
                ),
                // Orders with badge
                _navItemWithBadge(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  label: 'Orders',
                  index: 3,
                  badgeCount: prov.pendingOrderCount,
                ),
              ],
            ),
          ),
          drawer: _buildDrawer(context, prov),
        );
      },
    );
  }

  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive
                    ? AppTheme.primaryColor
                    : Colors.grey.shade500,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? AppTheme.primaryColor
                      : Colors.grey.shade500,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItemWithBadge({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required int badgeCount,
  }) {
    final isActive = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isActive ? activeIcon : icon,
                    color: isActive
                        ? AppTheme.primaryColor
                        : Colors.grey.shade500,
                    size: 22,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 14, minHeight: 14),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? AppTheme.primaryColor
                      : Colors.grey.shade500,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, InventoryProvider prov) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.warehouse,
                        color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'InventoryVault',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Powered by HiveVault',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statBadge(
                          '${prov.allProducts.length}', 'products'),
                      const SizedBox(width: 12),
                      _statBadge(
                          '${prov.categories.length}', 'categories'),
                      if (prov.unreadAlertCount > 0) ...[
                        const SizedBox(width: 12),
                        _statBadge(
                            '${prov.unreadAlertCount}', 'alerts',
                            color: Colors.orange),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Navigation items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 4),

                  // Search
                  _drawerItem(
                    context,
                    icon: Icons.search,
                    label: 'Global Search',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.search);
                    },
                  ),

                  const Divider(height: 1),
                  _drawerSection('Reports'),
                  _drawerItem(
                    context,
                    icon: Icons.bar_chart_outlined,
                    label: 'All Reports',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 4);
                    },
                  ),

                  const Divider(height: 1),

                  // Inventory
                  _drawerSection('Inventory'),
                  _drawerItem(
                    context,
                    icon: Icons.folder_outlined,
                    label: 'Categories',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.categories);
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.business_outlined,
                    label: 'Suppliers',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.suppliers);
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.swap_vert,
                    label: 'Stock Movements',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                          context, AppRoutes.stockMovements);
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.checklist,
                    label: 'Inventory Count',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                          context, AppRoutes.inventoryCount);
                    },
                  ),

                  const Divider(height: 1),

                  // Tools
                  _drawerSection('Tools'),
                  _drawerItem(
                    context,
                    icon: Icons.qr_code_scanner,
                    label: 'Barcode Scanner',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.scanner);
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.refresh,
                    label: 'Run Alert Scan',
                    onTap: () async {
                      Navigator.pop(context);
                      final count = await prov.runAlertScan();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Alert scan: $count new alert(s) found'),
                      ));
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.auto_awesome,
                    label: 'Auto Reorder',
                    onTap: () async {
                      Navigator.pop(context);
                      final count =
                          await prov.createReorderRequests();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '$count reorder request(s) created'),
                      ));
                    },
                  ),

                  const Divider(height: 1),

                  // Team
                  _drawerSection('Team'),
                  _drawerItem(
                    context,
                    icon: Icons.group_outlined,
                    label: 'Team Management',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.team);
                    },
                  ),

                  const Divider(height: 1),

                  // App
                  _drawerSection('App'),
                  _drawerItem(
                    context,
                    icon: Icons.people_outline,
                    label: 'Team Members',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                          context, AppRoutes.team);
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.settings);
                    },
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'InventoryVault v1.0.0 • AES-256-GCM encrypted',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String value, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color?.withOpacity(0.3) ?? Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _drawerSection(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.grey.shade500),
        ),
      );

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) =>
      ListTile(
        leading: Icon(icon, size: 22),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: trailing,
        onTap: onTap,
        dense: true,
      );
}
