// example/inventory_app/lib/screens/suppliers/suppliers_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Suppliers list with search, add, edit, delete, and detail navigation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/supplier.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/empty_state.dart';
import '../../theme/app_theme.dart';
import 'supplier_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public helper: open the Add-Supplier form from any screen.
// e.g. called from PurchaseOrderFormScreen when no suppliers exist.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> showAddSupplierForm(BuildContext context) async {
  final prov = context.read<InventoryProvider>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => ChangeNotifierProvider.value(
      value: prov,
      child: const _SupplierForm(),
    ),
  );
}

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
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
        final filtered = prov.suppliers.where((s) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          return s.name.toLowerCase().contains(q) ||
              (s.email?.toLowerCase().contains(q) ?? false) ||
              (s.contactName?.toLowerCase().contains(q) ?? false) ||
              (s.phone?.toLowerCase().contains(q) ?? false);
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Suppliers (${prov.suppliers.length})'),
          ),
          body: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search suppliers…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),

              // List
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.business_outlined,
                        title: _query.isEmpty
                            ? 'No Suppliers Yet'
                            : 'No Matching Suppliers',
                        subtitle: _query.isEmpty
                            ? 'Add your first supplier to get started'
                            : 'Try a different search term',
                        action: _query.isEmpty
                            ? ElevatedButton.icon(
                                onPressed: () => _showForm(context, prov),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Supplier'),
                              )
                            : TextButton(
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                                child: const Text('Clear Search'),
                              ),
                      )
                    : RefreshIndicator(
                        onRefresh: prov.loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final s = filtered[index];
                            return _SupplierCard(
                              supplier: s,
                              productCount: prov.allProducts
                                  .where((p) => p.supplierId == s.id)
                                  .length,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SupplierDetailScreen(supplier: s),
                                ),
                              ),
                              onEdit: () =>
                                  _showForm(context, prov, existing: s),
                              onDelete: () => _confirmDelete(context, prov, s),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showForm(context, prov),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showForm(BuildContext context, InventoryProvider prov,
      {Supplier? existing}) {
    // Pass the outer context so the modal sheet can access the provider
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => ChangeNotifierProvider.value(
        value: prov,
        child: _SupplierForm(existing: existing),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, InventoryProvider prov, Supplier s) {
    final productCount =
        prov.allProducts.where((p) => p.supplierId == s.id).length;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${s.name}"?'),
            if (productCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$productCount product(s) are linked to this supplier. '
                        'The supplier reference will be removed.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await prov.deleteSupplier(s.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Supplier "${s.name}" deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Supplier card ─────────────────────────────────────────────────────────────

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final int productCount;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _SupplierCard({
    required this.supplier,
    required this.productCount,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
                child: Text(
                  s.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (!s.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Inactive',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ),
                      ],
                    ),
                    if (s.contactName != null) ...[
                      const SizedBox(height: 2),
                      Text(s.contactName!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Star rating
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < s.rating.round()
                                ? Icons.star
                                : Icons.star_border,
                            size: 12,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$productCount product${productCount != 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.schedule_outlined,
                            size: 11, color: Colors.grey),
                        const SizedBox(width: 2),
                        Text(
                          '${s.defaultLeadTimeDays.toInt()}d lead',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions column
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: Colors.red.shade400),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supplier form ─────────────────────────────────────────────────────────────

class _SupplierForm extends StatefulWidget {
  final Supplier? existing;
  const _SupplierForm({this.existing});

  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

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
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _contactCtrl = TextEditingController(text: s?.contactName ?? '');
    _emailCtrl = TextEditingController(text: s?.email ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _websiteCtrl = TextEditingController(text: s?.website ?? '');
    _taxCtrl = TextEditingController(text: s?.taxNumber ?? '');
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
    _leadTimeCtrl = TextEditingController(
        text: s?.defaultLeadTimeDays.toStringAsFixed(0) ?? '7');
    _rating = s?.rating ?? 0;
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _contactCtrl,
      _emailCtrl,
      _phoneCtrl,
      _addressCtrl,
      _websiteCtrl,
      _taxCtrl,
      _notesCtrl,
      _leadTimeCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
              widget.existing == null ? 'Add Supplier' : 'Edit Supplier',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'Supplier Name *',
                icon: Icons.business_outlined,
                validator: (v) => v!.isEmpty ? 'Required' : null),
            _field(_contactCtrl, 'Contact Person', icon: Icons.person_outline),
            _field(_emailCtrl, 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress),
            _field(_phoneCtrl, 'Phone',
                icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
            _field(_addressCtrl, 'Address',
                icon: Icons.location_on_outlined, maxLines: 2),
            _field(_websiteCtrl, 'Website',
                icon: Icons.language_outlined, keyboardType: TextInputType.url),
            _field(_taxCtrl, 'Tax / VAT Number',
                icon: Icons.receipt_long_outlined),
            _field(_leadTimeCtrl, 'Lead Time (days)',
                icon: Icons.schedule_outlined,
                keyboardType: TextInputType.number),
            _field(_notesCtrl, 'Notes',
                icon: Icons.notes_outlined, maxLines: 3),
            const SizedBox(height: 8),

            // Rating
            const Text('Rating',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _rating = (i + 1).toDouble()),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        i < _rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _rating > 0 ? _rating.toStringAsFixed(1) : 'Not rated',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Active toggle
            SwitchListTile(
              title: const Text('Active Supplier'),
              subtitle:
                  const Text('Inactive suppliers won\'t appear in new orders'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

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
                    : const Icon(Icons.save_outlined),
                label: Text(widget.existing == null
                    ? 'Add Supplier'
                    : 'Update Supplier'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    IconData? icon,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon != null ? Icon(icon) : null,
          ),
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final prov = context.read<InventoryProvider>();
    final supplier = Supplier(
      id: widget.existing?.id ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      contactName:
          _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      address:
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      website:
          _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      taxNumber: _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      defaultLeadTimeDays: double.tryParse(_leadTimeCtrl.text) ?? 7,
      rating: _rating,
      isActive: _isActive,
      createdAt: widget.existing?.createdAt,
    );

    await prov.saveSupplier(supplier);
    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(widget.existing == null
              ? 'Supplier "${supplier.name}" added!'
              : 'Supplier updated!')),
    );
  }
}
