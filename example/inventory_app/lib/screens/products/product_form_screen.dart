// example/inventory_app/lib/screens/products/product_form_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/product.dart';
import '../../providers/inventory_provider.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;

  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  // Controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _currentStockCtrl;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _reorderPointCtrl;
  late final TextEditingController _reorderQtyCtrl;
  late final TextEditingController _maxStockCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _sellCtrl;

  String? _selectedCategoryId;
  String? _selectedSupplierId;
  UnitOfMeasure _unit = UnitOfMeasure.pieces;
  ProductStatus _status = ProductStatus.active;
  bool _isSaving = false;

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _locationCtrl = TextEditingController(text: p?.location ?? '');
    _currentStockCtrl =
        TextEditingController(text: p?.currentStock.toStringAsFixed(0) ?? '0');
    _minStockCtrl =
        TextEditingController(text: p?.minimumStock.toStringAsFixed(0) ?? '5');
    _reorderPointCtrl =
        TextEditingController(text: p?.reorderPoint.toStringAsFixed(0) ?? '10');
    _reorderQtyCtrl =
        TextEditingController(text: p?.reorderQty.toStringAsFixed(0) ?? '50');
    _maxStockCtrl =
        TextEditingController(text: p?.maximumStock.toStringAsFixed(0) ?? '500');
    _costCtrl =
        TextEditingController(text: p?.costPrice.toStringAsFixed(2) ?? '0.00');
    _sellCtrl =
        TextEditingController(text: p?.sellingPrice.toStringAsFixed(2) ?? '0.00');
    _selectedCategoryId = p?.categoryId;
    _selectedSupplierId = p?.supplierId;
    _unit = p?.unit ?? UnitOfMeasure.pieces;
    _status = p?.status ?? ProductStatus.active;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _skuCtrl, _barcodeCtrl, _descCtrl, _locationCtrl,
      _currentStockCtrl, _minStockCtrl, _reorderPointCtrl, _reorderQtyCtrl,
      _maxStockCtrl, _costCtrl, _sellCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Product' : 'Add Product'),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                )
              else
                TextButton(
                  onPressed: () => _save(prov),
                  child: const Text('SAVE',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader('Basic Information'),
                _field(_nameCtrl, 'Product Name *',
                    validator: (v) =>
                        v!.isEmpty ? 'Required' : null),
                _field(_skuCtrl, 'SKU *',
                    validator: (v) => v!.isEmpty ? 'Required' : null),
                _field(_barcodeCtrl, 'Barcode (EAN/UPC)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Scan barcode using the Scanner tab'),
                            ),
                          ),
                    )),
                _field(_descCtrl, 'Description', maxLines: 2),
                _field(_locationCtrl, 'Warehouse Location (e.g. A-01-03)'),

                const SizedBox(height: 16),
                _sectionHeader('Classification'),
                _dropdownField<String?>(
                  label: 'Category *',
                  value: _selectedCategoryId,
                  items: prov.categories
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCategoryId = v),
                  validator: (v) => v == null ? 'Select a category' : null,
                ),
                _dropdownField<String?>(
                  label: 'Supplier',
                  value: _selectedSupplierId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('None')),
                    ...prov.suppliers.map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedSupplierId = v),
                ),
                _dropdownField<UnitOfMeasure>(
                  label: 'Unit of Measure',
                  value: _unit,
                  items: UnitOfMeasure.values
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _unit = v!),
                ),
                _dropdownField<ProductStatus>(
                  label: 'Status',
                  value: _status,
                  items: ProductStatus.values
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.name.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),

                const SizedBox(height: 16),
                _sectionHeader('Stock Levels'),
                Row(
                  children: [
                    Expanded(
                        child: _field(_currentStockCtrl, 'Current Stock',
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field(_minStockCtrl, 'Minimum Stock',
                            keyboardType: TextInputType.number)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: _field(_reorderPointCtrl, 'Reorder Point',
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field(_reorderQtyCtrl, 'Reorder Qty',
                            keyboardType: TextInputType.number)),
                  ],
                ),
                _field(_maxStockCtrl, 'Maximum Stock',
                    keyboardType: TextInputType.number),

                const SizedBox(height: 16),
                _sectionHeader('Pricing'),
                Row(
                  children: [
                    Expanded(
                        child: _field(_costCtrl, 'Cost Price (\$)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field(_sellCtrl, 'Selling Price (\$)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  ],
                ),

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : () => _save(prov),
                  child: Text(isEditing ? 'Update Product' : 'Add Product'),
                ),
                if (isEditing) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _deleteProduct(context, prov),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Delete Product'),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.grey),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: suffixIcon,
          ),
          validator: validator,
        ),
      );

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? Function(T?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _save(InventoryProvider prov) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final product = Product(
      id: widget.product?.id ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      categoryId: _selectedCategoryId!,
      supplierId: _selectedSupplierId,
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
      currentStock: double.tryParse(_currentStockCtrl.text) ?? 0,
      minimumStock: double.tryParse(_minStockCtrl.text) ?? 5,
      reorderPoint: double.tryParse(_reorderPointCtrl.text) ?? 10,
      reorderQty: double.tryParse(_reorderQtyCtrl.text) ?? 50,
      maximumStock: double.tryParse(_maxStockCtrl.text) ?? 500,
      costPrice: double.tryParse(_costCtrl.text) ?? 0,
      sellingPrice: double.tryParse(_sellCtrl.text) ?? 0,
      unit: _unit,
      status: _status,
    );

    final ok = await prov.saveProduct(product);
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(isEditing ? 'Product updated!' : 'Product added!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${prov.error ?? 'Unknown error'}')),
      );
    }
  }

  void _deleteProduct(BuildContext context, InventoryProvider prov) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Are you sure you want to delete ${widget.product!.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await prov.deleteProduct(widget.product!.id);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Product deleted')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
