// example/inventory_app/lib/screens/stock/stock_movement_form_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../providers/inventory_provider.dart';
import '../../theme/app_theme.dart';

/// Full-page screen for creating a stock movement (when no product is
/// pre-selected). Shows a product search step followed by the movement form.
class StockMovementFormScreen extends StatefulWidget {
  const StockMovementFormScreen({super.key});

  @override
  State<StockMovementFormScreen> createState() =>
      _StockMovementFormScreenState();
}

class _StockMovementFormScreenState extends State<StockMovementFormScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final products = prov.allProducts
            .where((p) {
              if (_query.isEmpty) return true;
              final q = _query.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.sku.toLowerCase().contains(q) ||
                  p.barcode.toLowerCase().contains(q);
            })
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        return Scaffold(
          appBar: AppBar(title: const Text('New Stock Movement')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search product by name, SKU, barcode…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No products available'
                              : 'No products match "$_query"',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 40),
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final p = products[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.primaryColor.withOpacity(0.1),
                              child: const Icon(
                                Icons.inventory_2_outlined,
                                color: AppTheme.primaryColor,
                                size: 18,
                              ),
                            ),
                            title: Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            subtitle: Text(
                              '${p.sku} • Stock: ${p.currentStock.toInt()} ${p.unit.name}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade400,
                            ),
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20)),
                                ),
                                builder: (_) => ChangeNotifierProvider.value(
                                  value: prov,
                                  child: StockMovementFormSheet(
                                    product: p,
                                    preferIn: true,
                                  ),
                                ),
                              ).then((_) {
                                if (mounted) Navigator.pop(context);
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StockMovementFormSheet extends StatefulWidget {
  final Product product;
  final bool preferIn;

  const StockMovementFormSheet({
    super.key,
    required this.product,
    this.preferIn = true,
  });

  @override
  State<StockMovementFormSheet> createState() =>
      _StockMovementFormSheetState();
}

class _StockMovementFormSheetState extends State<StockMovementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late MovementType _type;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.preferIn ? MovementType.stockIn : MovementType.stockOut;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isPositive => _type.isPositive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Record Movement',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.product.name,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Current Stock: ${widget.product.currentStock.toInt()} ${widget.product.unit.name}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Movement type selector
              const Text('Movement Type',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MovementType.values.map((t) {
                  final selected = t == _type;
                  final color = t.isPositive ? Colors.green : Colors.red;
                  return FilterChip(
                    label: Text(
                      t.label,
                      style: TextStyle(
                        color: selected ? Colors.white : color,
                        fontSize: 12,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _type = t),
                    backgroundColor: color.withOpacity(0.1),
                    selectedColor: color,
                    checkmarkColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Quantity
              TextFormField(
                controller: _qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quantity *',
                  suffixText: widget.product.unit.name,
                  prefixIcon: Icon(
                    _isPositive ? Icons.add : Icons.remove,
                    color: _isPositive ? Colors.green : Colors.red,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a positive number';
                  if (!_isPositive && n > widget.product.currentStock) {
                    return 'Cannot exceed current stock (${widget.product.currentStock.toInt()})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Reference
              TextFormField(
                controller: _refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reference (PO#, Invoice#, etc.)',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(_isPositive
                          ? Icons.add_circle
                          : Icons.remove_circle),
                  label: Text(_isSaving
                      ? 'Saving...'
                      : '${_type.label} Stock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final prov = context.read<InventoryProvider>();
    final ok = await prov.recordMovement(
      productId: widget.product.id,
      type: _type,
      quantity: double.parse(_qtyCtrl.text),
      reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      notes:
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.pop(context);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_type.label} recorded successfully!'),
          backgroundColor: _isPositive ? Colors.green : Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${prov.error ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
