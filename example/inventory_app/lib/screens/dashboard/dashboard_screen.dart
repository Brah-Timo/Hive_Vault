// example/inventory_app/lib/screens/dashboard/dashboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Enhanced dashboard with KPI cards, animated charts, quick actions,
// recent activity feed, low-stock section, and sales trend bar chart.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/stock_movement.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/loading_overlay.dart';
import '../../theme/app_theme.dart';
import '../products/product_list_screen.dart';
import '../alerts/alerts_screen.dart';
import '../orders/purchase_order_list_screen.dart';
import '../scanner/scanner_screen.dart';
import '../products/product_form_screen.dart';
import '../stock/stock_movement_form_screen.dart';
import '../../widgets/offline_banner.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  int _touchedPieIndex = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        return LoadingOverlay(
          isLoading: prov.isLoading,
          child: Scaffold(
            appBar: _buildAppBar(context, prov),
            body: RefreshIndicator(
              onRefresh: prov.loadAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeBanner(context, prov),
                    _buildKpiRow(context, prov),
                    _buildQuickActions(context, prov),
                    _buildMovementBarChart(context, prov),
                    _buildCategoryChart(context, prov),
                    _buildLowStockSection(context, prov),
                    _buildRecentMovementsSection(context, prov),
                    _buildTopProducts(context, prov),
                  ],
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'dashScanFab',
              onPressed: () => _openScanner(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
              backgroundColor: AppTheme.primaryColor,
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, InventoryProvider prov) {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warehouse, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('InventoryVault'),
        ],
      ),
      actions: [
        // Alert bell
        Stack(
          children: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertsScreen()),
              ),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Alerts',
            ),
            if (prov.unreadAlertCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${prov.unreadAlertCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showOptions(context, prov),
          tooltip: 'More options',
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner(BuildContext context, InventoryProvider prov) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';
    final today = DateFormat('EEEE, MMMM d').format(now);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  today,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                // Quick status row
                Row(
                  children: [
                    _quickBadge(
                      '${prov.allProducts.length}',
                      'products',
                      Icons.inventory_2_outlined,
                    ),
                    const SizedBox(width: 8),
                    if (prov.unreadAlertCount > 0)
                      _quickBadge(
                        '${prov.unreadAlertCount}',
                        'alerts',
                        Icons.warning_amber_outlined,
                        color: Colors.orange,
                      )
                    else
                      _quickBadge('OK', 'stock', Icons.check_circle_outline,
                          color: Colors.green.shade300),
                    const SizedBox(width: 8),
                    _quickBadge(
                      '${prov.pendingOrderCount}',
                      'orders',
                      Icons.shopping_cart_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warehouse, size: 36, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _quickBadge(String value, String label, IconData icon,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color?.withOpacity(0.25) ?? Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color?.withOpacity(0.5) ?? Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? Colors.white),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(BuildContext context, InventoryProvider prov) {
    final s = prov.summary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.85,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          StatCard(
            title: 'Total Products',
            value: s.totalProducts.toString(),
            subtitle: '${s.activeProducts} active',
            icon: Icons.inventory_2_outlined,
            color: AppTheme.primaryColor,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductListScreen()),
            ),
          ),
          StatCard(
            title: 'Low Stock',
            value: s.lowStockCount.toString(),
            subtitle: '${s.outOfStockCount} out of stock',
            icon: Icons.warning_amber_outlined,
            color: s.lowStockCount > 0
                ? AppTheme.warningColor
                : AppTheme.successColor,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsScreen()),
            ),
          ),
          StatCard(
            title: 'Pending Orders',
            value: s.pendingOrders.toString(),
            subtitle: 'Purchase orders',
            icon: Icons.shopping_cart_outlined,
            color: AppTheme.infoColor,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PurchaseOrderListScreen()),
            ),
          ),
          StatCard(
            title: 'Inventory Value',
            value: formatCurrency(s.totalCostValue),
            subtitle: 'Cost value',
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, InventoryProvider prov) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _actionBtn(
                    context,
                    icon: Icons.add_box_outlined,
                    label: 'Add Product',
                    color: AppTheme.primaryColor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProductFormScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    context,
                    icon: Icons.qr_code_scanner,
                    label: 'Scan Barcode',
                    color: AppTheme.secondaryColor,
                    onTap: () => _openScanner(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    context,
                    icon: Icons.swap_vert,
                    label: 'Stock Move',
                    color: AppTheme.warningColor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StockMovementFormScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    context,
                    icon: Icons.auto_awesome,
                    label: 'Reorder',
                    color: AppTheme.infoColor,
                    onTap: () async {
                      final count = await prov.createReorderRequests();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$count reorder(s) created')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementBarChart(BuildContext context, InventoryProvider prov) {
    // Build last 7 days movement counts
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });

    // Count IN vs OUT per day
    final inCounts = List<double>.filled(7, 0);
    final outCounts = List<double>.filled(7, 0);

    for (final m in prov.movements) {
      final mDay =
          DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      final idx = days.indexOf(mDay);
      if (idx == -1) continue;
      if (m.type.isPositive) {
        inCounts[idx] += m.quantity;
      } else {
        outCounts[idx] += m.quantity;
      }
    }

    final hasData = inCounts.any((v) => v > 0) || outCounts.any((v) => v > 0);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Stock Movement (7 days)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _legendDot(Colors.green, 'IN'),
                    const SizedBox(width: 8),
                    _legendDot(Colors.red.shade400, 'OUT'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: hasData
                  ? BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: [
                              ...inCounts,
                              ...outCounts,
                              1,
                            ].reduce((a, b) => a > b ? a : b) *
                            1.2,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (g, gi, rod, ri) {
                              final label = ri == 0 ? 'IN' : 'OUT';
                              return BarTooltipItem(
                                '$label\n${rod.toY.toInt()}',
                                const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              );
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: null,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= days.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    DateFormat('dd/M').format(days[idx]),
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.grey),
                                  ),
                                );
                              },
                              reservedSize: 20,
                            ),
                          ),
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        barGroups: List.generate(7, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: inCounts[i],
                                color: Colors.green.shade400,
                                width: 7,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                              BarChartRodData(
                                toY: outCounts[i],
                                color: Colors.red.shade400,
                                width: 7,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ],
                          );
                        }),
                      ),
                    )
                  : Center(
                      child: Text(
                        'No movement data yet.\nRecord some stock movements to see trends.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCategoryChart(BuildContext context, InventoryProvider prov) {
    final data = prov.summary.valueByCategory;
    if (data.isEmpty) return const SizedBox.shrink();

    final entries = data.entries.toList();
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF00897B),
      const Color(0xFFF57C00),
      const Color(0xFF6A1B9A),
      const Color(0xFFD32F2F),
      const Color(0xFF0288D1),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock Value by Category',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touchedPieIndex = response
                                      ?.touchedSection?.touchedSectionIndex ??
                                  -1;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sections: List.generate(entries.length, (i) {
                          final isTouched = i == _touchedPieIndex;
                          final pct = (entries[i].value / total) * 100;
                          return PieChartSectionData(
                            color: colors[i % colors.length],
                            value: entries[i].value,
                            title:
                                isTouched ? '${pct.toStringAsFixed(1)}%' : '',
                            radius: isTouched ? 65 : 55,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }),
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(entries.length, (i) {
                        final pct = (entries[i].value / total) * 100;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: colors[i % colors.length],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entries[i].key.length > 14
                                          ? '${entries[i].key.substring(0, 12)}…'
                                          : entries[i].key,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${pct.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockSection(BuildContext context, InventoryProvider prov) {
    final lowStock =
        prov.allProducts.where((p) => p.isLowStock).take(5).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber_outlined,
                color: AppTheme.warningColor,
                size: 20,
              ),
            ),
            title: Text(
              'Low Stock Products',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              lowStock.isEmpty
                  ? 'All products are well stocked!'
                  : '${prov.summary.lowStockCount} need attention',
            ),
            trailing: lowStock.isEmpty
                ? const Icon(Icons.check_circle, color: AppTheme.successColor)
                : TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AlertsScreen()),
                    ),
                    child: const Text('View All'),
                  ),
          ),
          if (lowStock.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Inventory levels are healthy',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ...lowStock.map((p) {
            final pct = p.minimumStock > 0
                ? (p.currentStock / p.minimumStock).clamp(0.0, 1.0)
                : 0.0;
            final cat = prov.categoryById(p.categoryId);
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: (p.isOutOfStock
                        ? AppTheme.errorColor
                        : AppTheme.warningColor)
                    .withOpacity(0.12),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: p.isOutOfStock
                      ? AppTheme.errorColor
                      : AppTheme.warningColor,
                ),
              ),
              title: Text(
                p.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${cat?.name ?? ''} • ${p.sku}',
                      style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct < 0.25
                            ? AppTheme.errorColor
                            : AppTheme.warningColor,
                      ),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${p.currentStock.toInt()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: p.isOutOfStock
                          ? AppTheme.errorColor
                          : AppTheme.warningColor,
                    ),
                  ),
                  Text(
                    'min: ${p.minimumStock.toInt()}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRecentMovementsSection(
      BuildContext context, InventoryProvider prov) {
    final movements = prov.movements.take(6).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_vert,
                  color: AppTheme.primaryColor, size: 20),
            ),
            title: Text(
              'Recent Movements',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'No stock movements recorded yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ...movements.map((m) {
            final product =
                prov.allProducts.where((p) => p.id == m.productId).firstOrNull;
            final isPositive = m.type.isPositive;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: isPositive
                    ? Colors.green.withOpacity(0.12)
                    : Colors.red.withOpacity(0.12),
                child: Icon(
                  isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 14,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
              title: Text(
                product?.name ?? m.productId,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${m.type.label} • ${timeAgo(m.createdAt)}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isPositive ? '+' : '-'}${m.quantity.toInt()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                  if (m.reference != null)
                    Text(
                      m.reference!,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTopProducts(BuildContext context, InventoryProvider prov) {
    if (prov.allProducts.isEmpty) return const SizedBox.shrink();

    // Top products by stock value
    final topProducts = List.from(prov.allProducts)
      ..sort((a, b) => b.stockValue.compareTo(a.stockValue));
    final top5 = topProducts.take(5).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.trending_up,
                  color: AppTheme.successColor, size: 20),
            ),
            title: Text(
              'Top Products by Value',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...top5.asMap().entries.map((entry) {
            final idx = entry.key;
            final p = entry.value;
            final cat = prov.categoryById(p.categoryId);
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              title: Text(
                p.name,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${cat?.name ?? ''} • ${p.currentStock.toInt()} units',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                formatCurrency(p.stockValue),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successColor,
                  fontSize: 13,
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
  }

  void _showOptions(BuildContext context, InventoryProvider prov) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Quick Options',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: AppTheme.infoColor),
              title: const Text('Run Alert Scan'),
              subtitle: const Text('Check all products for stock issues'),
              onTap: () async {
                Navigator.pop(context);
                final count = await prov.runAlertScan();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Alert scan complete: $count new alert(s)'),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined,
                  color: AppTheme.primaryColor),
              title: const Text('Create Reorder Requests'),
              subtitle: const Text('Auto-generate POs for low stock items'),
              onTap: () async {
                Navigator.pop(context);
                final count = await prov.createReorderRequests();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$count reorder request(s) created'),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object, color: Colors.orange),
              title: const Text('Load Demo Data'),
              subtitle: const Text('Seed sample products for testing'),
              onTap: () async {
                Navigator.pop(context);
                await prov.seedDemoData();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Demo data loaded!')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
