// example/inventory_app/lib/screens/orders/purchase_order_form_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Create / edit a Purchase Order.
//
// Key UX fix: when no suppliers exist yet the supplier dropdown is replaced
// with a prominent "Create Supplier" card so the user is never stuck with an
// empty picker.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/purchase_order.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../providers/inventory_provider.dart';
import '../../theme/app_theme.dart';
import '../suppliers/suppliers_screen.dart'
    show SuppliersScreen, showAddSupplierForm;

class PurchaseOrderFormScreen extends StatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  State<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  final _notesCtrl = TextEditingController();

  String? _selectedSupplierId;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDelivery;
  final List<_LineEntry> _lines = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  double get _totalAmount => _lines.fold(0.0, (sum, l) {
        final qty = double.tryParse(l.qtyCtrl.text) ?? 0;
        final cost = double.tryParse(l.costCtrl.text) ?? 0;
        return sum + qty * cost;
      });

  String _nextOrderNumber(InventoryProvider prov) {
    final year = DateTime.now().year;
    final seq = (prov.orders.length + 1).toString().padLeft(5, '0');
    return 'PO-$year-$seq';
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final hasSuppliers = prov.suppliers.isNotEmpty;

        // Keep selected supplier valid after a supplier is added
        if (_selectedSupplierId != null &&
            prov.suppliers.every((s) => s.id != _selectedSupplierId)) {
          _selectedSupplierId = null;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Create Purchase Order'),
            actions: [
              TextButton(
                onPressed: _isSaving ? null : () => _save(prov),
                child: const Text(
                  'CREATE',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Supplier picker ──────────────────────────────────────
                if (!hasSuppliers) ...[
                  _NoSupplierCard(onCreated: () => setState(() {})),
                  const SizedBox(height: 12),
                ] else ...[
                  DropdownButtonFormField<String>(
                    value: _selectedSupplierId,
                    decoration: const InputDecoration(
                      labelText: 'Supplier *',
                      prefixIcon: Icon(Icons.business),
                    ),
                    items: prov.suppliers
                        .where((s) => s.isActive)
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child:
                                  Text(s.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSupplierId = v),
                    validator: (v) =>
                        v == null ? 'Please select a supplier' : null,
                    hint: const Text('Select supplier…'),
                  ),
                  // Quick-link to add another supplier without leaving screen
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await showAddSupplierForm(context);
                        // Refresh – supplier list updated via provider
                        setState(() {});
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add New Supplier',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // ── Order date ──────────────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today,
                      color: AppTheme.primaryColor),
                  title: const Text('Order Date'),
                  subtitle: Text(
                    '${_orderDate.day}/${_orderDate.month}/${_orderDate.year}',
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _orderDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _orderDate = d);
                  },
                ),

                // ── Expected delivery ───────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_shipping_outlined,
                      color: AppTheme.secondaryColor),
                  title: const Text('Expected Delivery'),
                  subtitle: Text(_expectedDelivery == null
                      ? 'Not set — tap to choose'
                      : '${_expectedDelivery!.day}/${_expectedDelivery!.month}/${_expectedDelivery!.year}'),
                  trailing: _expectedDelivery != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _expectedDelivery = null),
                        )
                      : null,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _expectedDelivery ??
                          DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _expectedDelivery = d);
                  },
                ),
                const SizedBox(height: 12),

                // ── Notes ───────────────────────────────────────────────
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Order lines header ──────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Order Lines (${_lines.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    TextButton.icon(
                      onPressed: prov.allProducts.isEmpty
                          ? null
                          : () => _addLine(prov),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Product'),
                    ),
                  ],
                ),

                if (_lines.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.add_shopping_cart,
                            size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'No products added yet.\nTap "Add Product" to add order lines.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                // ── Line cards ──────────────────────────────────────────
                ..._lines.asMap().entries.map((e) {
                  final i = e.key;
                  final line = e.value;
                  return _LineCard(
                    line: line,
                    onRemove: () => setState(() => _lines.removeAt(i)),
                    onChanged: () => setState(() {}),
                  );
                }),

                // ── Total ───────────────────────────────────────────────
                if (_lines.isNotEmpty) ...[
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Order Total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '\$${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: (_isSaving || _lines.isEmpty || !hasSuppliers)
                      ? null
                      : () => _save(prov),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Create Purchase Order'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── _addLine dialog ───────────────────────────────────────────────────────

  void _addLine(InventoryProvider prov) {
    Product? selected;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: const Text('Add Product to Order'),
          content: SizedBox(
            width: double.maxFinite,
            child: DropdownButtonFormField<Product>(
              value: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: prov.allProducts
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (${p.sku})',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (p) => setDs(() => selected = p),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selected == null
                  ? null
                  : () {
                      // Prevent duplicates
                      if (_lines.any((l) => l.product.id == selected!.id)) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text('Product already in order'),
                        ));
                        return;
                      }
                      Navigator.pop(ctx);
                      setState(() {
                        _lines.add(_LineEntry(
                          product: selected!,
                          qtyCtrl: TextEditingController(
                              text: selected!.reorderQty.toStringAsFixed(0)),
                          costCtrl: TextEditingController(
                              text: selected!.costPrice.toStringAsFixed(2)),
                        ));
                      });
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ── _save ─────────────────────────────────────────────────────────────────

  Future<void> _save(InventoryProvider prov) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a supplier')));
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one product')));
      return;
    }

    setState(() => _isSaving = true);

    final supplier = prov.supplierById(_selectedSupplierId!);
    final order = PurchaseOrder(
      id: _uuid.v4(),
      orderNumber: _nextOrderNumber(prov),
      supplierId: _selectedSupplierId!,
      supplierName: supplier?.name ?? 'Unknown',
      orderDate: _orderDate,
      expectedDelivery: _expectedDelivery,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdBy: 'current_user',
      lines: _lines
          .map((l) => PurchaseOrderLine(
                productId: l.product.id,
                productName: l.product.name,
                sku: l.product.sku,
                orderedQty:
                    double.tryParse(l.qtyCtrl.text) ?? l.product.reorderQty,
                unitCost:
                    double.tryParse(l.costCtrl.text) ?? l.product.costPrice,
              ))
          .toList(),
    );

    final ok = await prov.createPurchaseOrder(order);
    setState(() => _isSaving = false);
    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Purchase order created successfully!')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ${prov.error}')));
    }
  }
}

// ── No-supplier banner ────────────────────────────────────────────────────────

class _NoSupplierCard extends StatelessWidget {
  final VoidCallback? onCreated;
  const _NoSupplierCard({this.onCreated});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade700, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'No suppliers yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'You must create at least one supplier before creating a '
            'purchase order.',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await showAddSupplierForm(context);
                onCreated?.call();
              },
              icon: const Icon(Icons.add_business),
              label: const Text('Create Supplier Now'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Line card ─────────────────────────────────────────────────────────────────

class _LineCard extends StatelessWidget {
  final _LineEntry line;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _LineCard(
      {required this.line, required this.onRemove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(line.qtyCtrl.text) ?? 0;
    final cost = double.tryParse(line.costCtrl.text) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(line.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            Text('SKU: ${line.product.sku}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: line.qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Qty', isDense: true),
                    onChanged: (_) => onChanged(),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      return (n == null || n <= 0) ? 'Invalid qty' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: line.costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Unit Cost (\$)', isDense: true),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      '\$${(qty * cost).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data holder ───────────────────────────────────────────────────────────────

class _LineEntry {
  final Product product;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  _LineEntry(
      {required this.product, required this.qtyCtrl, required this.costCtrl});
  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}
