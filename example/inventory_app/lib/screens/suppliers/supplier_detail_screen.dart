// example/inventory_app/lib/screens/suppliers/supplier_detail_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Supplier detail screen — shows full supplier info, linked products,
// associated purchase orders, and allows editing / deleting the supplier.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/supplier.dart';
import '../../models/product.dart';
import '../../models/purchase_order.dart';
import '../../providers/inventory_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class SupplierDetailScreen extends StatelessWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        // Get latest supplier data
        final current = prov.suppliers
                .where((s) => s.id == supplier.id)
                .firstOrNull ??
            supplier;

        final linkedProducts = prov.allProducts
            .where((p) => p.supplierId == current.id)
            .toList();

        final linkedOrders = prov.orders
            .where((o) => o.supplierId == current.id)
            .toList()
          ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit supplier',
                onPressed: () => _showEditForm(context, prov, current),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete supplier',
                onPressed: () => _confirmDelete(context, prov, current),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, current),
                const SizedBox(height: 12),
                _buildContactCard(context, current),
                const SizedBox(height: 12),
                _buildStatsRow(context, linkedProducts, linkedOrders),
                const SizedBox(height: 12),
                _buildProductsSection(context, linkedProducts, prov),
                const SizedBox(height: 12),
                _buildOrdersSection(context, linkedOrders),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Supplier s) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
              child: Text(
                s.name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (s.contactName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.contactName!,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Star rating
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Icon(
                          i < s.rating.round() ? Icons.star : Icons.star_border,
                          size: 16,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  if (!s.isActive) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Text(
                        'Inactive',
                        style: TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(BuildContext context, Supplier s) {
    final items = <Widget>[];

    if (s.email != null) {
      items.add(_contactRow(Icons.email_outlined, s.email!));
    }
    if (s.phone != null) {
      items.add(_contactRow(Icons.phone_outlined, s.phone!));
    }
    if (s.address != null) {
      items.add(_contactRow(Icons.location_on_outlined, s.address!));
    }
    if (s.website != null) {
      items.add(_contactRow(Icons.language_outlined, s.website!));
    }
    if (s.taxNumber != null) {
      items.add(_contactRow(Icons.receipt_outlined, 'Tax: ${s.taxNumber}'));
    }
    items.add(_contactRow(
        Icons.schedule_outlined,
        'Lead time: ${s.defaultLeadTimeDays.toInt()} days'));

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Information',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...items,
            if (s.notes != null && s.notes!.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                'Notes',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(s.notes!, style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    List<Product> products,
    List<PurchaseOrder> orders,
  ) {
    final totalOrderValue = orders.fold(
      0.0,
      (sum, o) => sum + o.lines.fold(0.0, (s, l) => s + l.lineTotal),
    );
    final activeOrders = orders
        .where((o) =>
            o.status != PurchaseOrderStatus.fullyReceived &&
            o.status != PurchaseOrderStatus.cancelled)
        .length;

    return Row(
      children: [
        Expanded(
          child: _miniStat(
            context,
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            value: products.length.toString(),
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            context,
            icon: Icons.shopping_cart_outlined,
            label: 'Orders',
            value: orders.length.toString(),
            color: AppTheme.infoColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat(
            context,
            icon: Icons.pending_outlined,
            label: 'Active',
            value: activeOrders.toString(),
            color: AppTheme.warningColor,
          ),
        ),
      ],
    );
  }

  Widget _miniStat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildProductsSection(
    BuildContext context,
    List<Product> products,
    InventoryProvider prov,
  ) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
            leading:
                const Icon(Icons.inventory_2_outlined, color: AppTheme.primaryColor),
            title: Text(
              'Linked Products (${products.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...products.take(5).map((p) {
            final cat = prov.categoryById(p.categoryId);
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: p.isLowStock
                    ? AppTheme.warningColor.withOpacity(0.15)
                    : AppTheme.successColor.withOpacity(0.12),
                child: Icon(
                  p.isLowStock ? Icons.warning_amber : Icons.check_circle,
                  size: 14,
                  color: p.isLowStock ? AppTheme.warningColor : AppTheme.successColor,
                ),
              ),
              title: Text(p.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${cat?.name ?? 'Unknown'} • ${p.sku}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${p.currentStock.toInt()} ${p.unit.name}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: p.isLowStock ? AppTheme.warningColor : Colors.grey,
                ),
              ),
            );
          }),
          if (products.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '+ ${products.length - 5} more products',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOrdersSection(BuildContext context, List<PurchaseOrder> orders) {
    if (orders.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined,
                color: AppTheme.infoColor),
            title: Text(
              'Purchase Orders (${orders.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...orders.take(5).map((o) {
            final total =
                o.lines.fold(0.0, (sum, l) => sum + l.lineTotal);
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: _orderStatusColor(o.status).withOpacity(0.15),
                child: Icon(
                  _orderStatusIcon(o.status),
                  size: 14,
                  color: _orderStatusColor(o.status),
                ),
              ),
              title: Text(o.orderNumber, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                DateFormat('dd MMM yyyy').format(o.orderDate),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _orderStatusColor(o.status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      o.status.label,
                      style: TextStyle(
                        fontSize: 9,
                        color: _orderStatusColor(o.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

  Color _orderStatusColor(PurchaseOrderStatus status) => switch (status) {
        PurchaseOrderStatus.draft => Colors.grey,
        PurchaseOrderStatus.submitted => AppTheme.infoColor,
        PurchaseOrderStatus.approved => Colors.teal,
        PurchaseOrderStatus.sent => AppTheme.primaryColor,
        PurchaseOrderStatus.partiallyReceived => AppTheme.warningColor,
        PurchaseOrderStatus.fullyReceived => AppTheme.successColor,
        PurchaseOrderStatus.cancelled => AppTheme.errorColor,
      };

  IconData _orderStatusIcon(PurchaseOrderStatus status) => switch (status) {
        PurchaseOrderStatus.draft => Icons.description_outlined,
        PurchaseOrderStatus.submitted => Icons.send_outlined,
        PurchaseOrderStatus.approved => Icons.thumb_up_outlined,
        PurchaseOrderStatus.sent => Icons.local_shipping_outlined,
        PurchaseOrderStatus.partiallyReceived => Icons.inventory_outlined,
        PurchaseOrderStatus.fullyReceived => Icons.check_circle_outline,
        PurchaseOrderStatus.cancelled => Icons.cancel_outlined,
      };

  void _showEditForm(
      BuildContext context, InventoryProvider prov, Supplier supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: prov,
        child: _SupplierEditForm(supplier: supplier),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, InventoryProvider prov, Supplier supplier) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text(
            'Are you sure you want to delete "${supplier.name}"? '
            'This will not remove linked products.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await prov.deleteSupplier(supplier.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Supplier deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Inline edit form ─────────────────────────────────────────────────────────

class _SupplierEditForm extends StatefulWidget {
  final Supplier supplier;
  const _SupplierEditForm({required this.supplier});

  @override
  State<_SupplierEditForm> createState() => _SupplierEditFormState();
}

class _SupplierEditFormState extends State<_SupplierEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _leadTimeCtrl;
  double _rating = 0;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameCtrl = TextEditingController(text: s.name);
    _contactCtrl = TextEditingController(text: s.contactName ?? '');
    _emailCtrl = TextEditingController(text: s.email ?? '');
    _phoneCtrl = TextEditingController(text: s.phone ?? '');
    _addressCtrl = TextEditingController(text: s.address ?? '');
    _websiteCtrl = TextEditingController(text: s.website ?? '');
    _taxCtrl = TextEditingController(text: s.taxNumber ?? '');
    _notesCtrl = TextEditingController(text: s.notes ?? '');
    _leadTimeCtrl = TextEditingController(
        text: s.defaultLeadTimeDays.toStringAsFixed(0));
    _rating = s.rating;
    _isActive = s.isActive;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _contactCtrl, _emailCtrl, _phoneCtrl,
      _addressCtrl, _websiteCtrl, _taxCtrl, _notesCtrl, _leadTimeCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Form(
        key: _formKey,
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
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
            Text(
              'Edit Supplier',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'Supplier Name *',
                validator: (v) => v!.isEmpty ? 'Required' : null),
            _field(_contactCtrl, 'Contact Person'),
            _field(_emailCtrl, 'Email',
                keyboardType: TextInputType.emailAddress),
            _field(_phoneCtrl, 'Phone', keyboardType: TextInputType.phone),
            _field(_addressCtrl, 'Address', maxLines: 2),
            _field(_websiteCtrl, 'Website', keyboardType: TextInputType.url),
            _field(_taxCtrl, 'Tax / VAT Number'),
            _field(_leadTimeCtrl, 'Default Lead Time (days)',
                keyboardType: TextInputType.number),
            _field(_notesCtrl, 'Notes', maxLines: 3),
            const SizedBox(height: 8),
            // Rating
            Row(
              children: [
                const Text('Rating:', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                ...List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _rating = (i + 1).toDouble()),
                    child: Icon(
                      i < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_rating.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            // Active toggle
            SwitchListTile(
              title: const Text('Active Supplier'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update Supplier'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {int maxLines = 1,
      String? Function(String?)? validator,
      TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final prov = context.read<InventoryProvider>();
    final updated = Supplier(
      id: widget.supplier.id,
      name: _nameCtrl.text.trim(),
      contactName:
          _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      address:
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      website:
          _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      taxNumber:
          _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      defaultLeadTimeDays: double.tryParse(_leadTimeCtrl.text) ?? 7,
      rating: _rating,
      isActive: _isActive,
      createdAt: widget.supplier.createdAt,
    );

    await prov.saveSupplier(updated);
    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supplier updated!')),
    );
  }
}
