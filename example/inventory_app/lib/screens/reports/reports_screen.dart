// example/inventory_app/lib/screens/reports/reports_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reports hub — Low Stock, Valuation, Movements, Reorder, Summary charts.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/inventory_report.dart';
import '../../models/stock_movement.dart';
import '../../providers/inventory_provider.dart';
import '../../services/pdf_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reports Hub
// ─────────────────────────────────────────────────────────────────────────────

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _SectionTitle('Inventory Reports'),
          _ReportCard(
            icon: Icons.warning_amber_outlined,
            color: AppTheme.warningColor,
            title: 'Low Stock Report',
            subtitle: 'Products below minimum stock level',
            onGenerate: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _LowStockReportPage())),
          ),
          _ReportCard(
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.successColor,
            title: 'Valuation Report',
            subtitle: 'Inventory cost & selling value breakdown',
            onGenerate: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const _ValuationReportPage())),
          ),
          _ReportCard(
            icon: Icons.swap_vert,
            color: AppTheme.primaryColor,
            title: 'Stock Movements',
            subtitle: 'In/out history with date range filter',
            onGenerate: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _MovementReportPage())),
          ),
          _ReportCard(
            icon: Icons.shopping_cart_outlined,
            color: AppTheme.infoColor,
            title: 'Reorder Report',
            subtitle: 'Products that need to be reordered',
            onGenerate: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _ReorderReportPage())),
          ),
          _ReportCard(
            icon: Icons.dashboard_outlined,
            color: const Color(0xFF6A1B9A),
            title: 'Summary Report',
            subtitle: 'Category totals & overall KPIs',
            onGenerate: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _SummaryReportPage())),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey.shade600,
          ),
        ),
      );
}

class _ReportCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onGenerate;

  const _ReportCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: onGenerate,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: const Text('View'),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Low Stock Report
// ─────────────────────────────────────────────────────────────────────────────

class _LowStockReportPage extends StatefulWidget {
  const _LowStockReportPage();

  @override
  State<_LowStockReportPage> createState() => _LowStockReportPageState();
}

class _LowStockReportPageState extends State<_LowStockReportPage> {
  late Future<List<LowStockItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<InventoryProvider>().getLowStockReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock Report'),
        actions: [
          FutureBuilder<List<LowStockItem>>(
            future: _future,
            builder: (_, snap) => IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed:
                  snap.hasData ? () => _exportPdf(context, snap.data!) : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<LowStockItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No Low Stock Items',
              subtitle: 'All products are above minimum stock level.',
            );
          }
          return Column(
            children: [
              _buildSummaryBanner(items),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final pct = item.minimumStock > 0
                        ? (item.currentStock / item.minimumStock)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item.isCritical
                            ? AppTheme.errorColor.withOpacity(0.12)
                            : AppTheme.warningColor.withOpacity(0.12),
                        child: Icon(
                          item.isCritical
                              ? Icons.remove_shopping_cart
                              : Icons.warning_amber,
                          size: 20,
                          color: item.isCritical
                              ? AppTheme.errorColor
                              : AppTheme.warningColor,
                        ),
                      ),
                      title: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item.sku} • ${item.categoryName}',
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                pct == 0
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
                            '${item.currentStock.toInt()}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: item.isCritical
                                  ? AppTheme.errorColor
                                  : AppTheme.warningColor,
                            ),
                          ),
                          Text(
                            'min: ${item.minimumStock.toInt()}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBanner(List<LowStockItem> items) {
    final outOf = items.where((i) => i.isCritical).length;
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.warningColor.withOpacity(0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bannerStat('Total', '${items.length}', AppTheme.warningColor),
          _bannerStat('Out of Stock', '$outOf', AppTheme.errorColor),
          _bannerStat(
              'Need Reorder', '${items.length - outOf}', AppTheme.infoColor),
        ],
      ),
    );
  }

  Widget _bannerStat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 22, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Future<void> _exportPdf(
      BuildContext context, List<LowStockItem> items) async {
    await PdfService.printLowStockReport(items);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Valuation Report
// ─────────────────────────────────────────────────────────────────────────────

class _ValuationReportPage extends StatefulWidget {
  const _ValuationReportPage();

  @override
  State<_ValuationReportPage> createState() => _ValuationReportPageState();
}

class _ValuationReportPageState extends State<_ValuationReportPage> {
  late Future<List<ValuationItem>> _future;
  int _touchedIdx = -1;

  @override
  void initState() {
    super.initState();
    _future = context.read<InventoryProvider>().getValuationReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Valuation Report'),
        actions: [
          FutureBuilder<List<ValuationItem>>(
            future: _future,
            builder: (_, snap) => IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed:
                  snap.hasData ? () => _exportPdf(context, snap.data!) : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<ValuationItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No Valuation Data',
              subtitle: 'Add products with cost prices to see valuation.',
            );
          }
          final totalCost = items.fold(0.0, (s, i) => s + i.costValue);
          final totalSell = items.fold(0.0, (s, i) => s + i.sellingValue);

          return ListView(
            children: [
              _buildPieChart(items, totalCost),
              _buildTotalsRow(totalCost, totalSell),
              const Divider(),
              ...items.map((item) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.successColor.withOpacity(0.12),
                      child: const Icon(Icons.inventory_2_outlined,
                          size: 20, color: AppTheme.successColor),
                    ),
                    title: Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${item.categoryName} • Qty: ${item.quantity.toInt()}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatCurrency(item.costValue),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.successColor),
                        ),
                        Text(
                          'Sell: ${formatCurrency(item.sellingValue)}',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPieChart(List<ValuationItem> items, double totalCost) {
    if (totalCost == 0) return const SizedBox.shrink();
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF00897B),
      const Color(0xFFF57C00),
      const Color(0xFF6A1B9A),
      const Color(0xFFD32F2F),
      const Color(0xFF0288D1),
    ];
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cost Value Distribution',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
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
                              _touchedIdx = response
                                      ?.touchedSection?.touchedSectionIndex ??
                                  -1;
                            });
                          },
                        ),
                        sections: List.generate(items.length, (i) {
                          final pct = (items[i].costValue / totalCost) * 100;
                          final touched = i == _touchedIdx;
                          return PieChartSectionData(
                            color: colors[i % colors.length],
                            value: items[i].costValue,
                            title: touched ? '${pct.toStringAsFixed(1)}%' : '',
                            radius: touched ? 65 : 52,
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          );
                        }),
                        centerSpaceRadius: 28,
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(items.length.clamp(0, 6), (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: colors[i % colors.length],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              items[i].name.length > 13
                                  ? '${items[i].name.substring(0, 11)}…'
                                  : items[i].name,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsRow(double cost, double sell) {
    final margin = sell > 0 ? ((sell - cost) / sell * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
              child: _valueTile(
                  'Total Cost', formatCurrency(cost), AppTheme.successColor)),
          Expanded(
              child: _valueTile('Total Selling', formatCurrency(sell),
                  AppTheme.primaryColor)),
          Expanded(
              child: _valueTile('Gross Margin', '${margin.toStringAsFixed(1)}%',
                  AppTheme.secondaryColor)),
        ],
      ),
    );
  }

  Widget _valueTile(String label, String value, Color color) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );

  Future<void> _exportPdf(
      BuildContext context, List<ValuationItem> items) async {
    await PdfService.printValuationReport(items);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Movement Report (with date range + bar chart)
// ─────────────────────────────────────────────────────────────────────────────

class _MovementReportPage extends StatefulWidget {
  const _MovementReportPage();

  @override
  State<_MovementReportPage> createState() => _MovementReportPageState();
}

class _MovementReportPageState extends State<_MovementReportPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Future<List<StockMovement>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<InventoryProvider>().getMovementReport(
            from: _from,
            to: _to,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Movements')),
      body: Column(
        children: [
          // Date range filter
          _buildDateFilter(),
          // Content
          Expanded(
            child: FutureBuilder<List<StockMovement>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final movements = snap.data ?? [];
                if (movements.isEmpty) {
                  return const EmptyState(
                    icon: Icons.swap_vert,
                    title: 'No Movements',
                    subtitle: 'No stock movements in selected range.',
                  );
                }
                final inQty = movements
                    .where((m) => m.type.isPositive)
                    .fold(0.0, (s, m) => s + m.quantity);
                final outQty = movements
                    .where((m) => !m.type.isPositive)
                    .fold(0.0, (s, m) => s + m.quantity);

                return ListView(
                  children: [
                    _buildMovementChart(movements),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                              child: _countChip(
                                  'Stock In', inQty.toInt(), Colors.green)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _countChip('Stock Out', outQty.toInt(),
                                  AppTheme.errorColor)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _countChip('Total Txns', movements.length,
                                  AppTheme.primaryColor)),
                        ],
                      ),
                    ),
                    const Divider(),
                    ...movements.map((m) {
                      final prov = context.read<InventoryProvider>();
                      final product = prov.allProducts
                          .where((p) => p.id == m.productId)
                          .firstOrNull;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: m.type.isPositive
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          child: Icon(
                            m.type.isPositive
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 14,
                            color:
                                m.type.isPositive ? Colors.green : Colors.red,
                          ),
                        ),
                        title: Text(product?.name ?? m.productId,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${m.type.label} • ${DateFormat('dd MMM HH:mm').format(m.createdAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          '${m.type.isPositive ? '+' : '-'}${m.quantity.toInt()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                m.type.isPositive ? Colors.green : Colors.red,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementChart(List<StockMovement> movements) {
    // Group by day (last 7 active days)
    final Map<String, double> inByDay = {};
    final Map<String, double> outByDay = {};
    for (final m in movements) {
      final key = DateFormat('MM/dd').format(m.createdAt);
      if (m.type.isPositive) {
        inByDay[key] = (inByDay[key] ?? 0) + m.quantity;
      } else {
        outByDay[key] = (outByDay[key] ?? 0) + m.quantity;
      }
    }
    final days = {...inByDay.keys, ...outByDay.keys}.toList()..sort();
    final visible = days.length > 7 ? days.sublist(days.length - 7) : days;

    if (visible.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Movement Overview',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= visible.length)
                            return const SizedBox();
                          return Text(
                            visible[idx],
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(visible.length, (i) {
                    final day = visible[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: inByDay[day] ?? 0,
                          color: Colors.green,
                          width: 7,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: outByDay[day] ?? 0,
                          color: AppTheme.errorColor,
                          width: 7,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(Colors.green, 'In'),
                const SizedBox(width: 16),
                _legend(AppTheme.errorColor, 'Out'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        children: [
          Container(width: 10, height: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _countChip(String label, int value, Color color) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 18, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: DateTimeRange(start: _from, end: _to),
                );
                if (picked != null) {
                  _from = picked.start;
                  _to = picked.end;
                  _load();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${DateFormat('dd MMM').format(_from)} – '
                  '${DateFormat('dd MMM yyyy').format(_to)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              _from = DateTime.now().subtract(const Duration(days: 30));
              _to = DateTime.now();
              _load();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reorder Report
// ─────────────────────────────────────────────────────────────────────────────

class _ReorderReportPage extends StatefulWidget {
  const _ReorderReportPage();

  @override
  State<_ReorderReportPage> createState() => _ReorderReportPageState();
}

class _ReorderReportPageState extends State<_ReorderReportPage> {
  late Future<List<LowStockItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<InventoryProvider>().getReorderReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: _createReorders,
            tooltip: 'Create purchase orders',
          ),
        ],
      ),
      body: FutureBuilder<List<LowStockItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No Reorder Needed',
              subtitle: 'All products are above reorder point.',
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.infoColor.withOpacity(0.12),
                  child: const Icon(Icons.shopping_cart_outlined,
                      size: 20, color: AppTheme.infoColor),
                ),
                title: Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${item.sku} • Stock: ${item.currentStock.toInt()} '
                    '(min: ${item.minimumStock.toInt()})',
                    style: const TextStyle(fontSize: 12)),
                trailing: Chip(
                  backgroundColor: AppTheme.infoColor.withOpacity(0.1),
                  label: Text(
                    'Order ${item.reorderQty.toInt()}',
                    style: const TextStyle(
                        color: AppTheme.infoColor, fontSize: 11),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createReorders() async {
    final prov = context.read<InventoryProvider>();
    final count = await prov.createReorderRequests();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count purchase order(s) created')));
    Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Report
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryReportPage extends StatelessWidget {
  const _SummaryReportPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Summary')),
      body: Consumer<InventoryProvider>(
        builder: (context, prov, _) {
          final s = prov.summary;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // KPI cards
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                children: [
                  _kpiCard('Total Products', '${s.totalProducts}',
                      Icons.inventory_2, AppTheme.primaryColor),
                  _kpiCard('Active Products', '${s.activeProducts}',
                      Icons.check_circle, AppTheme.successColor),
                  _kpiCard('Low Stock', '${s.lowStockCount}',
                      Icons.warning_amber, AppTheme.warningColor),
                  _kpiCard('Out of Stock', '${s.outOfStockCount}',
                      Icons.remove_shopping_cart, AppTheme.errorColor),
                  _kpiCard('Cost Value', formatCurrency(s.totalCostValue),
                      Icons.account_balance_wallet, AppTheme.successColor),
                  _kpiCard('Selling Value', formatCurrency(s.totalSellingValue),
                      Icons.sell, AppTheme.primaryColor),
                ],
              ),
              const SizedBox(height: 12),

              // By category
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Value by Category',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...s.valueByCategory.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.key)),
                              Text(formatCurrency(e.value),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(label,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey))),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          ],
        ),
      ),
    );
  }
}
