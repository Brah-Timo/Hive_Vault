// example/inventory_app/lib/screens/inventory/inventory_count_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Inventory Counting / Stocktake — record physical count and reconcile
// differences with the system stock.
//
// Web-safe: the embedded barcode scanner is only shown on non-web platforms.
// On web, users can still search/type barcodes manually.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// mobile_scanner is only available on native platforms (not web)
// ignore: depend_on_referenced_packages
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) '../../utils/scanner_stub.dart';

import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';

/// Per-line entry during a stocktake session.
class CountEntry {
  final Product product;
  double counted;
  bool confirmed;
  bool scanned;

  CountEntry({
    required this.product,
    this.counted = 0,
    this.confirmed = false,
    this.scanned = false,
  });

  double get variance => counted - product.currentStock;
  bool get hasVariance => variance.abs() > 0.001;
}

class InventoryCountScreen extends StatefulWidget {
  const InventoryCountScreen({super.key});

  @override
  State<InventoryCountScreen> createState() => _InventoryCountScreenState();
}

class _InventoryCountScreenState extends State<InventoryCountScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  final List<CountEntry> _entries = [];
  final _searchCtrl = TextEditingController();
  bool _scannerOpen = false;
  bool _showVariancesOnly = false;
  bool _isSubmitting = false;
  late TabController _tabController;
  MobileScannerController? _scannerController;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initEntries());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _initEntries() async {
    final prov = context.read<InventoryProvider>();
    final products = prov.allProducts
        .where((p) => p.status == ProductStatus.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    setState(() {
      _entries.clear();
      _entries.addAll(products.map((p) => CountEntry(product: p)));
    });
  }

  // ── Filter ──────────────────────────────────────────────────────────────────

  List<CountEntry> get _filteredEntries {
    var result = _entries;
    if (_searchCtrl.text.isNotEmpty) {
      final q = _searchCtrl.text.toLowerCase();
      result = result
          .where((e) =>
              e.product.name.toLowerCase().contains(q) ||
              e.product.sku.toLowerCase().contains(q) ||
              e.product.barcode.toLowerCase().contains(q))
          .toList();
    }
    if (_showVariancesOnly) {
      result = result.where((e) => e.confirmed && e.hasVariance).toList();
    }
    return result;
  }

  int get _totalConfirmed => _entries.where((e) => e.confirmed).length;
  int get _totalVariances =>
      _entries.where((e) => e.confirmed && e.hasVariance).length;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Count'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              text: 'Count (${_entries.length})',
              icon: const Icon(Icons.list_alt, size: 18),
            ),
            Tab(
              text: 'Variances ($_totalVariances)',
              icon: const Icon(Icons.difference, size: 18),
            ),
          ],
        ),
        actions: [
          // Only show scanner toggle on native platforms
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _toggleScanner,
              tooltip: 'Scan barcode',
            ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _totalConfirmed > 0 ? _submitCount : null,
            tooltip: 'Apply count adjustments',
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgress(),

          // Barcode scanner (native only, collapsible)
          if (!kIsWeb && _scannerOpen) _buildMiniScanner(),

          // Web barcode entry banner
          if (kIsWeb) _buildWebBarcodeBanner(),

          // Search + filter bar
          _buildSearchBar(),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCountList(),
                _buildVarianceList(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildProgress() {
    final progress =
        _entries.isEmpty ? 0.0 : _totalConfirmed / _entries.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_totalConfirmed / ${_entries.length} counted',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: progress == 1.0
                        ? AppTheme.successColor
                        : AppTheme.primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress == 1.0
                    ? AppTheme.successColor
                    : AppTheme.primaryColor,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniScanner() {
    return Container(
      height: 160,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor, width: 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (raw != null) _onBarcodeScanned(raw);
            },
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _toggleScanner,
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebBarcodeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.infoColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppTheme.infoColor),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Camera unavailable on web — use the search bar or tap a row to set its count.',
              style: TextStyle(fontSize: 11, color: AppTheme.infoColor),
            ),
          ),
          TextButton(
            onPressed: _showWebBarcodeEntry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Enter Barcode', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by name, SKU or barcode…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Variances', style: TextStyle(fontSize: 11)),
            selected: _showVariancesOnly,
            onSelected: (v) => setState(() => _showVariancesOnly = v),
            selectedColor: AppTheme.warningColor.withOpacity(0.2),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildCountList() {
    final entries = _filteredEntries;
    if (entries.isEmpty && _entries.isEmpty) {
      return EmptyState(
        icon: Icons.list_alt,
        title: 'Nothing to Count',
        subtitle: 'Add active products first.',
        action: ElevatedButton.icon(
          onPressed: _initEntries,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload'),
        ),
      );
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No Results',
        subtitle: 'Try adjusting the search query.',
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, i) => _buildCountTile(entries[i]),
    );
  }

  Widget _buildCountTile(CountEntry entry) {
    final isConfirmed = entry.confirmed;
    final variance = entry.variance;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isConfirmed
            ? BorderSide(
                color: entry.hasVariance
                    ? AppTheme.warningColor
                    : AppTheme.successColor,
                width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status icon
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                isConfirmed
                    ? (entry.hasVariance
                        ? Icons.warning_amber
                        : Icons.check_circle)
                    : Icons.radio_button_unchecked,
                color: isConfirmed
                    ? (entry.hasVariance
                        ? AppTheme.warningColor
                        : AppTheme.successColor)
                    : Colors.grey.shade400,
                size: 22,
              ),
            ),

            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.scanned)
                        const Icon(Icons.qr_code,
                            size: 14, color: Colors.grey),
                    ],
                  ),
                  Text(
                    '${entry.product.sku} • System: '
                    '${formatNumber(entry.product.currentStock)} ${entry.product.unit.name}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (isConfirmed && entry.hasVariance) ...[
                    const SizedBox(height: 2),
                    Text(
                      variance > 0
                          ? '+${variance.toInt()} surplus'
                          : '${variance.toInt()} short',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: variance > 0
                            ? AppTheme.infoColor
                            : AppTheme.errorColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Count controls
            _buildCountControls(entry),

            // Confirm checkbox
            Checkbox(
              value: entry.confirmed,
              activeColor: AppTheme.primaryColor,
              onChanged: (_) =>
                  setState(() => entry.confirmed = !entry.confirmed),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountControls(CountEntry entry) {
    return SizedBox(
      width: 96,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconBtn(
            icon: Icons.remove,
            color: Colors.grey.shade200,
            iconColor: Colors.black87,
            onTap: () => setState(() {
              if (entry.counted > 0) entry.counted--;
            }),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _editCount(entry),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  entry.counted.toInt().toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
          _iconBtn(
            icon: Icons.add,
            color: AppTheme.primaryColor.withOpacity(0.15),
            iconColor: AppTheme.primaryColor,
            onTap: () => setState(() => entry.counted++),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      );

  Widget _buildVarianceList() {
    final variances =
        _entries.where((e) => e.confirmed && e.hasVariance).toList();
    if (variances.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No Variances',
        subtitle: 'All confirmed counts match system stock.',
      );
    }
    return ListView.builder(
      itemCount: variances.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, i) {
        final e = variances[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: e.variance < 0
                ? AppTheme.errorColor.withOpacity(0.12)
                : AppTheme.infoColor.withOpacity(0.12),
            child: Icon(
              e.variance < 0 ? Icons.trending_down : Icons.trending_up,
              color: e.variance < 0
                  ? AppTheme.errorColor
                  : AppTheme.infoColor,
              size: 20,
            ),
          ),
          title: Text(e.product.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              'System: ${e.product.currentStock.toInt()}  →  '
              'Counted: ${e.counted.toInt()}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            '${e.variance > 0 ? '+' : ''}${e.variance.toInt()}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color:
                  e.variance < 0 ? AppTheme.errorColor : AppTheme.infoColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final confirmed = _totalConfirmed;
    final variances = _totalVariances;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, -2))
          ],
        ),
        child: Row(
          children: [
            _summaryChip(Icons.done_all, '$confirmed confirmed',
                AppTheme.successColor),
            const SizedBox(width: 8),
            _summaryChip(Icons.warning_amber, '$variances variances',
                variances > 0 ? AppTheme.warningColor : Colors.grey),
            const Spacer(),
            ElevatedButton.icon(
              onPressed:
                  confirmed > 0 && !_isSubmitting ? _submitCount : null,
              icon: const Icon(Icons.check_circle),
              label: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      );

  // ── Interactions ──────────────────────────────────────────────────────────

  void _toggleScanner() {
    if (_scannerOpen) {
      _scannerController?.dispose();
      _scannerController = null;
    } else {
      _scannerController = MobileScannerController();
    }
    setState(() => _scannerOpen = !_scannerOpen);
  }

  void _onBarcodeScanned(String barcode) {
    final idx = _entries.indexWhere(
        (e) => e.product.barcode == barcode || e.product.sku == barcode);
    if (idx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No product found for: $barcode'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final entry = _entries[idx];
    setState(() {
      entry.counted++;
      entry.scanned = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('${entry.product.name} counted: ${entry.counted.toInt()}'),
      duration: const Duration(seconds: 1),
    ));
  }

  void _showWebBarcodeEntry() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Find Product by Barcode / SKU'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode or SKU',
            prefixIcon: Icon(Icons.qr_code),
          ),
          onSubmitted: (v) {
            Navigator.pop(context);
            _onBarcodeScanned(v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (ctrl.text.trim().isNotEmpty) {
                _onBarcodeScanned(ctrl.text.trim());
              }
            },
            child: const Text('Find'),
          ),
        ],
      ),
    );
  }

  void _editCount(CountEntry entry) {
    final ctrl =
        TextEditingController(text: entry.counted.toInt().toString());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Count: ${entry.product.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
          ],
          decoration: InputDecoration(
            labelText: 'Physical Count',
            suffixText: entry.product.unit.name,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text) ?? 0;
              setState(() {
                entry.counted = v;
                entry.confirmed = true;
              });
              Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCount() async {
    final toAdjust =
        _entries.where((e) => e.confirmed && e.hasVariance).toList();
    if (toAdjust.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No variances to apply — all counts match system stock.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apply Stocktake Adjustments?'),
        content: Text(
          '${toAdjust.length} item(s) have variances.\n'
          'Stock levels will be adjusted to match physical counts.\n\n'
          'Confirmed: $_totalConfirmed / ${_entries.length} products.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply Adjustments'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    final prov = context.read<InventoryProvider>();

    for (final e in toAdjust) {
      await prov.adjustStockToCount(
        productId: e.product.id,
        physicalCount: e.counted,
        notes: 'Stocktake adjustment',
      );
    }

    setState(() => _isSubmitting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${toAdjust.length} adjustment(s) applied successfully'),
        backgroundColor: AppTheme.successColor,
      ));
      Navigator.pop(context);
    }
  }
}
