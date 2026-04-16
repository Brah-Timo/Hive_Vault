// example/inventory_app/lib/screens/categories/categories_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Categories screen — grid view with product counts, add/edit/delete.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/category.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/empty_state.dart';
import '../../theme/app_theme.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final categories = prov.categories;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Categories'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload defaults',
                onPressed: prov.initialize,
              ),
            ],
          ),
          body: categories.isEmpty
              ? EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'No Categories',
                  subtitle: 'Default categories will be added automatically',
                  action: ElevatedButton(
                    onPressed: prov.initialize,
                    child: const Text('Load Defaults'),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final productCount = prov.allProducts
                        .where((p) => p.categoryId == cat.id)
                        .length;

                    return _CategoryTile(
                      category: cat,
                      productCount: productCount,
                      onEdit: () => _showForm(context, prov, existing: cat),
                      onDelete: productCount > 0
                          ? null
                          : () => _confirmDelete(context, prov, cat),
                    );
                  },
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
      {ProductCategory? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CategoryForm(existing: existing),
    );
  }

  void _confirmDelete(
      BuildContext context, InventoryProvider prov, ProductCategory cat) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${cat.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await prov.deleteCategory(cat.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Category "${cat.name}" deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ProductCategory category;
  final int productCount;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryTile({
    required this.category,
    required this.productCount,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: category.color.withOpacity(0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: category.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.folder_rounded,
                      color: category.color,
                      size: 22,
                    ),
                  ),
                  Row(
                    children: [
                      if (onEdit != null)
                        InkWell(
                          onTap: onEdit,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined,
                                size: 16, color: category.color),
                          ),
                        ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline,
                                size: 16, color: Colors.red.shade400),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: category.color,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: category.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$productCount product${productCount != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: category.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _CategoryForm extends StatefulWidget {
  final ProductCategory? existing;
  const _CategoryForm({this.existing});

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  int _colorValue = 0xFF2196F3;
  bool _isSaving = false;

  final _colors = [
    0xFF1565C0,
    0xFF00897B,
    0xFF6A1B9A,
    0xFFD32F2F,
    0xFFF57C00,
    0xFF2E7D32,
    0xFF0288D1,
    0xFF4E342E,
    0xFFE65100,
    0xFFD81B60,
    0xFF00695C,
    0xFF558B2F,
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _colorValue = widget.existing?.colorValue ?? 0xFF2196F3;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = Color(_colorValue);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

              // Title with preview
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selectedColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.folder_rounded,
                        color: selectedColor, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add Category'
                          : 'Edit Category',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Category Name *',
                    prefixIcon: Icon(Icons.label_outline)),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(Icons.description_outlined)),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Category Color',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colors.map((c) {
                  final selected = c == _colorValue;
                  return GestureDetector(
                    onTap: () => setState(() => _colorValue = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: Colors.black, width: 3)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Color(c).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
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
                      ? 'Add Category'
                      : 'Update Category'),
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
    final category = ProductCategory(
      id: widget.existing?.id ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      colorValue: _colorValue,
      createdAt: widget.existing?.createdAt,
    );

    await prov.saveCategory(category);
    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(widget.existing == null
              ? 'Category "${category.name}" added!'
              : 'Category updated!')),
    );
  }
}
