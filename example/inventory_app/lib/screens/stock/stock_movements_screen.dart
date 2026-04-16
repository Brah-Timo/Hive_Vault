// example/inventory_app/lib/screens/stock/stock_movements_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Full stock movement log — filter, sort, date range, detail view, PDF export.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/stock_movement.dart';
import '../../services/pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'stock_movement_form_screen.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  String _search = '';
  MovementType? _typeFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  final _searchCtrl = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StockMovement> _buildFilteredList(InventoryProvider prov) {
    var list = List<StockMovement>.from(prov.movements);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      final names = {for (final p in prov.allProducts) p.id: p.name.toLowerCase()};
      list = list
          .where((m) =>
              (names[m.productId]?.contains(q) ?? false) ||
              (m.reference?.toLowerCase().contains(q) ?? false) ||
              (m.notes?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_typeFilter != null) {
      list = list.where((m) => m.type == _typeFilter).toList();
    }
    if (_fromDate != null) {
      list = list.where((m) => !m.createdAt.isBefore(_fromDate!)).toList();
    }
    if (_toDate != null) {
      final end = _toDate!.add(const Duration(days: 1));
      list = list.where((m) => m.createdAt.isBefore(end)).toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  bool get _hasFilters =>
      _typeFilter != null || _fromDate != null || _toDate != null || _search.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _search = '';
      _typeFilter = null;
      _fromDate = null;
      _toDate = null;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final movements = _buildFilteredList(prov);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Stock Movements'),
            actions: [
              IconButton(
                icon: const Icon(Icons.date_range),
                tooltip: 'Date filter',
                onPressed: () => _showDateFilter(context),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Type filter',
                onPressed: () => _showTypeFilter(context),
              ),
              IconButton(
                icon: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf),
                tooltip: 'Export PDF',
                onPressed: _exporting ? null : () => _exportPdf(movements),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchBar(),
              if (_hasFilters) _buildActiveFilters(),
              _buildSummaryRow(movements),
              Expanded(
                child: movements.isEmpty
                    ? EmptyState(
                        icon: Icons.swap_vert,
                        title: 'No Movements',
                        subtitle: _hasFilters
                            ? 'No movements match your filters.'
                            : 'Record stock movements to see them here.',
                        action: _hasFilters
                            ? ElevatedButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear Filters'),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _addMovement(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Movement'),
                              ),
                      )
                    : RefreshIndicator(
                        onRefresh: prov.loadAll,
                        child: ListView.builder(
                          itemCount: movements.length,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemBuilder: (context, i) {
                            final m = movements[i];
                            final product = prov.allProducts
                                .where((p) => p.id == m.productId)
                                .firstOrNull;
                            return _MovementTile(
                              movement: m,
                              productName: product?.name ?? m.productId,
                              onTap: () => _showDetail(
                                  context, m, product?.name ?? m.productId),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addMovement(context),
            icon: const Icon(Icons.add),
            label: const Text('New Movement'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Search by product, reference, notes…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    })
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      );

  Widget _buildActiveFilters() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            if (_typeFilter != null)
              _chip(
                  _typeFilter!.label,
                  _typeFilter!.isPositive ? Colors.green : Colors.red,
                  () => setState(() => _typeFilter = null)),
            if (_fromDate != null)
              _chip(
                  'From: ${DateFormat('dd/MM').format(_fromDate!)}',
                  AppTheme.primaryColor,
                  () => setState(() => _fromDate = null)),
            if (_toDate != null)
              _chip(
                  'To: ${DateFormat('dd/MM').format(_toDate!)}',
                  AppTheme.primaryColor,
                  () => setState(() => _toDate = null)),
            const SizedBox(width: 4),
            ActionChip(
              label: const Text('Clear All'),
              onPressed: _clearFilters,
              side: BorderSide.none,
              backgroundColor: Colors.grey.shade200,
              labelStyle: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );

  Widget _chip(String label, Color color, VoidCallback onRemove) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Chip(
          label: Text(label,
              style: TextStyle(fontSize: 11, color: color)),
          deleteIcon: const Icon(Icons.close, size: 14),
          onDeleted: onRemove,
          backgroundColor: color.withOpacity(0.08),
          side: BorderSide(color: color.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _buildSummaryRow(List<StockMovement> list) {
    final totalIn = list.where((m) => m.type.isPositive).fold(0.0, (s, m) => s + m.quantity);
    final totalOut = list.where((m) => !m.type.isPositive).fold(0.0, (s, m) => s + m.quantity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(child: _summaryPill('${list.length} records', Icons.list_alt, Colors.blueGrey)),
        const SizedBox(width: 8),
        Expanded(child: _summaryPill('+${totalIn.toInt()} IN', Icons.arrow_downward, Colors.green)),
        const SizedBox(width: 8),
        Expanded(child: _summaryPill('-${totalOut.toInt()} OUT', Icons.arrow_upward, Colors.red)),
      ]),
    );
  }

  Widget _summaryPill(String label, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _showTypeFilter(BuildContext context) {
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
                    borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Filter by Type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('All Types'),
              trailing: _typeFilter == null
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : null,
              onTap: () {
                setState(() => _typeFilter = null);
                Navigator.pop(context);
              },
            ),
            ...MovementType.values.map((t) => ListTile(
                  leading: Icon(
                      t.isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                      color: t.isPositive ? Colors.green : Colors.red),
                  title: Text(t.label),
                  trailing: _typeFilter == t
                      ? const Icon(Icons.check, color: AppTheme.primaryColor)
                      : null,
                  onTap: () {
                    setState(() => _typeFilter = t);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showDateFilter(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: (_fromDate != null && _toDate != null)
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
    }
  }

  void _showDetail(BuildContext context, StockMovement m, String productName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _MovementDetail(movement: m, productName: productName),
    );
  }

  void _addMovement(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const StockMovementFormScreen()));
  }

  Future<void> _exportPdf(List<StockMovement> movements) async {
    if (movements.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No movements to export')));
      return;
    }
    setState(() => _exporting = true);
    try {
      await PdfService.printMovementReport(movements);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  final String productName;
  final VoidCallback onTap;
  const _MovementTile(
      {required this.movement,
      required this.productName,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isPos = m.type.isPositive;
    final color = isPos ? Colors.green : AppTheme.errorColor;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(isPos ? Icons.arrow_downward : Icons.arrow_upward,
              size: 18, color: color),
        ),
        title: Text(productName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(m.type.label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Text(DateFormat('dd MMM yyyy HH:mm').format(m.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if (m.reference != null)
              Text('Ref: ${m.reference}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${isPos ? '+' : '-'}${m.quantity.toInt()}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text('→ ${m.stockAfter.toInt()}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MovementDetail extends StatelessWidget {
  final StockMovement movement;
  final String productName;
  const _MovementDetail({required this.movement, required this.productName});

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isPos = m.type.isPositive;
    final color = isPos ? Colors.green : AppTheme.errorColor;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          // Header card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.2))),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                radius: 24,
                child: Icon(isPos ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(m.type.label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(height: 4),
                  Text(productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${isPos ? '+' : '-'}${m.quantity.toInt()}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        color: color)),
                Text('units',
                    style: TextStyle(
                        fontSize: 11, color: color.withOpacity(0.7))),
              ]),
            ]),
          ),
          // Stock flow
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                  child: _stockBox(
                      'Before', '${m.stockBefore.toInt()}', Colors.blueGrey)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: color, size: 20)),
              Expanded(
                  child: _stockBox('After', '${m.stockAfter.toInt()}', color)),
            ]),
          ),
          _row('Date & Time',
              DateFormat('dd MMM yyyy HH:mm').format(m.createdAt)),
          if (m.reference != null) _row('Reference', m.reference!),
          if (m.notes != null) _row('Notes', m.notes!),
          if (m.userId != null) _row('Performed By', m.userId!),
          if (m.locationFrom != null) _row('From Location', m.locationFrom!),
          if (m.locationTo != null) _row('To Location', m.locationTo!),
          _row('Movement ID', m.id, mono: true),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _stockBox(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const Text('units',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      );

  Widget _row(String label, String value, {bool mono = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade100, width: 1))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      fontFamily: mono ? 'monospace' : null))),
        ]),
      );
}
