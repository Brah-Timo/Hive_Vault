// example/inventory_app/lib/screens/products/product_list_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Product list with full-text search, category/status filtering, and sorting.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../../widgets/product_card.dart';
import '../../widgets/empty_state.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';
import '../stock/stock_movement_form_screen.dart';

enum _SortOption {
  nameAsc,
  nameDesc,
  stockAsc,
  stockDesc,
  valueDesc,
  valueAsc,
  newestFirst,
  oldestFirst,
}

extension _SortOptionX on _SortOption {
  String get label => switch (this) {
        _SortOption.nameAsc => 'Name (A → Z)',
        _SortOption.nameDesc => 'Name (Z → A)',
        _SortOption.stockAsc => 'Stock (Low → High)',
        _SortOption.stockDesc => 'Stock (High → Low)',
        _SortOption.valueDesc => 'Value (High → Low)',
        _SortOption.valueAsc => 'Value (Low → High)',
        _SortOption.newestFirst => 'Newest First',
        _SortOption.oldestFirst => 'Oldest First',
      };

  IconData get icon => switch (this) {
        _SortOption.nameAsc => Icons.sort_by_alpha,
        _SortOption.nameDesc => Icons.sort_by_alpha,
        _SortOption.stockAsc => Icons.arrow_upward,
        _SortOption.stockDesc => Icons.arrow_downward,
        _SortOption.valueDesc => Icons.monetization_on,
        _SortOption.valueAsc => Icons.money_off,
        _SortOption.newestFirst => Icons.access_time,
        _SortOption.oldestFirst => Icons.history,
      };
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _searchController = TextEditingController();
  _SortOption _sortOption = _SortOption.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _sortProducts(List<Product> input) {
    final list = List<Product>.from(input);
    switch (_sortOption) {
      case _SortOption.nameAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortOption.nameDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _SortOption.stockAsc:
        list.sort((a, b) => a.currentStock.compareTo(b.currentStock));
        break;
      case _SortOption.stockDesc:
        list.sort((a, b) => b.currentStock.compareTo(a.currentStock));
        break;
      case _SortOption.valueDesc:
        list.sort((a, b) => b.stockValue.compareTo(a.stockValue));
        break;
      case _SortOption.valueAsc:
        list.sort((a, b) => a.stockValue.compareTo(b.stockValue));
        break;
      case _SortOption.newestFirst:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortOption.oldestFirst:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final sorted = _sortProducts(prov.products);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Products'),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter',
                onPressed: () => _showFilterSheet(context, prov),
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                onPressed: () => _showSortSheet(context),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchBar(context, prov),
              _buildFilterChips(context, prov),
              // Sort indicator
              if (_sortOption != _SortOption.nameAsc)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(_sortOption.icon, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Sorted by: ${_sortOption.label}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            setState(() => _sortOption = _SortOption.nameAsc),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 24),
                        ),
                        child:
                            const Text('Reset', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: sorted.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: prov.productSearch.isEmpty &&
                                prov.selectedCategoryFilter == null
                            ? 'No Products Yet'
                            : 'No Matching Products',
                        subtitle: prov.productSearch.isEmpty
                            ? 'Add your first product to get started'
                            : 'Try adjusting the search or filters',
                        action: prov.productSearch.isEmpty
                            ? ElevatedButton.icon(
                                onPressed: () => _addProduct(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Product'),
                              )
                            : TextButton(
                                onPressed: () {
                                  prov.clearFilters();
                                  _searchController.clear();
                                },
                                child: const Text('Clear Filters'),
                              ),
                      )
                    : RefreshIndicator(
                        onRefresh: prov.loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: sorted.length,
                          itemBuilder: (context, index) {
                            final product = sorted[index];
                            final cat = prov.categoryById(product.categoryId);
                            return ProductCard(
                              product: product,
                              categoryName: cat?.name,
                              onTap: () => _viewProduct(context, product),
                              onEdit: () => _editProduct(context, product),
                              onAddStock: () => _addStock(context, product),
                              onDelete: () =>
                                  _confirmDelete(context, prov, product),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'scanFab',
                onPressed: () => Navigator.pushNamed(context, '/scanner'),
                tooltip: 'Scan Barcode',
                child: const Icon(Icons.qr_code_scanner),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'addFab',
                onPressed: () => _addProduct(context),
                tooltip: 'Add Product',
                child: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context, InventoryProvider prov) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name, SKU, or barcode...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    prov.setProductSearch('');
                  },
                  icon: const Icon(Icons.clear),
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: prov.setProductSearch,
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, InventoryProvider prov) {
    final hasFilter =
        prov.selectedCategoryFilter != null || prov.statusFilter != null;

    if (prov.categories.isEmpty && !hasFilter) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          if (hasFilter) ...[
            ActionChip(
              avatar: const Icon(Icons.clear, size: 14),
              label: const Text('Clear'),
              onPressed: () {
                prov.clearFilters();
                _searchController.clear();
              },
            ),
            const SizedBox(width: 8),
          ],
          // Status chips
          ...ProductStatus.values.map((status) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(status.name),
                  selected: prov.statusFilter == status,
                  onSelected: (sel) =>
                      prov.setStatusFilter(sel ? status : null),
                ),
              )),
          ...prov.categories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat.name),
                  selected: prov.selectedCategoryFilter == cat.id,
                  onSelected: (sel) =>
                      prov.setCategoryFilter(sel ? cat.id : null),
                  avatar: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cat.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  void _addProduct(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
  }

  void _editProduct(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
  }

  void _viewProduct(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _addStock(BuildContext context, Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StockMovementFormSheet(product: product),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, InventoryProvider prov, Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text(
          'Are you sure you want to delete "${product.name}"?\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final success = await prov.deleteProduct(product.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? '"${product.name}" deleted'
              : 'Failed to delete product'),
          backgroundColor: success ? null : Colors.red,
        ));
      }
    }
  }

  void _showFilterSheet(BuildContext context, InventoryProvider prov) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Filter by Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...ProductStatus.values.map((status) => ListTile(
                  title: Text(status.name.toUpperCase()),
                  leading: Radio<ProductStatus?>(
                    value: status,
                    groupValue: prov.statusFilter,
                    onChanged: (v) {
                      prov.setStatusFilter(v);
                      Navigator.pop(context);
                    },
                  ),
                )),
            ListTile(
              title: const Text('ALL'),
              leading: Radio<ProductStatus?>(
                value: null,
                groupValue: prov.statusFilter,
                onChanged: (v) {
                  prov.setStatusFilter(null);
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const Text('Sort Products',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ..._SortOption.values.map((opt) => RadioListTile<_SortOption>(
                      title: Row(
                        children: [
                          Icon(opt.icon, size: 18, color: Colors.grey),
                          const SizedBox(width: 10),
                          Text(opt.label, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      value: opt,
                      groupValue: _sortOption,
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _sortOption = v);
                          setModalState(() {});
                        }
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}
