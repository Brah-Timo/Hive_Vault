// example/inventory_app/lib/screens/search/global_search_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Global search across products, categories, suppliers, and purchase orders.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../models/purchase_order.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stock_status_badge.dart';
import '../../utils/formatters.dart';
import '../products/product_detail_screen.dart';
import '../products/product_form_screen.dart';
import '../suppliers/supplier_detail_screen.dart';
import '../orders/purchase_order_detail_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  late final TabController _tabController;

  static const _tabLabels = ['All', 'Products', 'Suppliers', 'Orders'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white70,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search products, suppliers, orders…',
            hintStyle: const TextStyle(color: Colors.white54),
            border: InputBorder.none,
            filled: false,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _query.isEmpty
          ? _buildEmptyPrompt()
          : Consumer<InventoryProvider>(
              builder: (context, prov, _) {
                final q = _query.toLowerCase();

                final products = prov.allProducts
                    .where((p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.sku.toLowerCase().contains(q) ||
                        p.barcode.toLowerCase().contains(q) ||
                        (p.description?.toLowerCase().contains(q) ?? false) ||
                        (p.location?.toLowerCase().contains(q) ?? false))
                    .toList();

                final suppliers = prov.suppliers
                    .where((s) =>
                        s.name.toLowerCase().contains(q) ||
                        (s.email?.toLowerCase().contains(q) ?? false) ||
                        (s.contactName?.toLowerCase().contains(q) ?? false) ||
                        (s.phone?.toLowerCase().contains(q) ?? false))
                    .toList();

                final categories = prov.categories
                    .where((c) =>
                        c.name.toLowerCase().contains(q) ||
                        (c.description?.toLowerCase().contains(q) ?? false))
                    .toList();

                final orders = prov.orders
                    .where((o) =>
                        o.orderNumber.toLowerCase().contains(q) ||
                        o.supplierName.toLowerCase().contains(q) ||
                        (o.notes?.toLowerCase().contains(q) ?? false))
                    .toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    // All results
                    _buildAllTab(context, products, suppliers, categories,
                        orders, prov, q),
                    // Products tab
                    _buildProductsTab(context, products, prov),
                    // Suppliers tab
                    _buildSuppliersTab(context, suppliers),
                    // Orders tab
                    _buildOrdersTab(context, orders),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEmptyPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.manage_search, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Search across everything',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Products • Suppliers • Purchase Orders\nSKU • Barcode • Location',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTab(
    BuildContext context,
    List<Product> products,
    List<Supplier> suppliers,
    List categories,
    List<PurchaseOrder> orders,
    InventoryProvider prov,
    String q,
  ) {
    final hasResults = products.isNotEmpty ||
        suppliers.isNotEmpty ||
        categories.isNotEmpty ||
        orders.isNotEmpty;

    if (!hasResults) {
      return _buildNoResults(context, q);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            '${products.length + suppliers.length + categories.length + orders.length} results for "$_query"',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        if (products.isNotEmpty) ...[
          _sectionHeader('Products', products.length, Icons.inventory_2),
          ...products.take(3).map((p) => _buildProductTile(context, p, prov)),
          if (products.length > 3)
            _showMoreButton(
              'View all ${products.length} products',
              () => _tabController.animateTo(1),
            ),
        ],
        if (suppliers.isNotEmpty) ...[
          _sectionHeader('Suppliers', suppliers.length, Icons.business),
          ...suppliers.take(3).map((s) => _buildSupplierTile(context, s)),
          if (suppliers.length > 3)
            _showMoreButton(
              'View all ${suppliers.length} suppliers',
              () => _tabController.animateTo(2),
            ),
        ],
        if (orders.isNotEmpty) ...[
          _sectionHeader('Purchase Orders', orders.length, Icons.shopping_cart),
          ...orders.take(3).map((o) => _buildOrderTile(context, o)),
          if (orders.length > 3)
            _showMoreButton(
              'View all ${orders.length} orders',
              () => _tabController.animateTo(3),
            ),
        ],
        if (categories.isNotEmpty) ...[
          _sectionHeader('Categories', categories.length, Icons.folder),
          ...categories.map((c) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.color.withOpacity(0.15),
                  child: Icon(Icons.folder_outlined, color: c.color, size: 20),
                ),
                title: Text(c.name),
                subtitle: c.description != null
                    ? Text(c.description!, style: const TextStyle(fontSize: 12))
                    : null,
              )),
        ],
      ],
    );
  }

  Widget _buildProductsTab(
      BuildContext context, List<Product> products, InventoryProvider prov) {
    if (products.isEmpty) {
      return _buildNoResults(context, _query,
          onCreate: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProductFormScreen())));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: products.length,
      itemBuilder: (ctx, i) => _buildProductTile(ctx, products[i], prov),
    );
  }

  Widget _buildSuppliersTab(BuildContext context, List<Supplier> suppliers) {
    if (suppliers.isEmpty) return _buildNoResults(context, _query);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: suppliers.length,
      itemBuilder: (ctx, i) => _buildSupplierTile(ctx, suppliers[i]),
    );
  }

  Widget _buildOrdersTab(BuildContext context, List<PurchaseOrder> orders) {
    if (orders.isEmpty) return _buildNoResults(context, _query);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: orders.length,
      itemBuilder: (ctx, i) => _buildOrderTile(ctx, orders[i]),
    );
  }

  Widget _buildNoResults(BuildContext context, String query,
      {VoidCallback? onCreate}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'No results for "$query"',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create New Product'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          Text(
            '$title ($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _showMoreButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildProductTile(
      BuildContext context, Product p, InventoryProvider prov) {
    final cat = prov.categoryById(p.categoryId);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: p.isOutOfStock
            ? AppTheme.errorColor.withOpacity(0.12)
            : p.isLowStock
                ? AppTheme.warningColor.withOpacity(0.12)
                : AppTheme.primaryColor.withOpacity(0.12),
        child: Icon(
          Icons.inventory_2_outlined,
          size: 20,
          color: p.isOutOfStock
              ? AppTheme.errorColor
              : p.isLowStock
                  ? AppTheme.warningColor
                  : AppTheme.primaryColor,
        ),
      ),
      title: Text(p.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${p.sku} • ${cat?.name ?? 'Uncategorised'} • ${p.currentStock.toInt()} ${p.unit.name}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: StockStatusBadge(product: p),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
      ),
    );
  }

  Widget _buildSupplierTile(BuildContext context, Supplier s) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.secondaryColor.withOpacity(0.12),
        child: Text(
          s.name.substring(0, 1).toUpperCase(),
          style: const TextStyle(
              color: AppTheme.secondaryColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(s.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        [s.contactName, s.email, s.phone]
            .where((x) => x != null && x.isNotEmpty)
            .join(' • '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            i < s.rating.round() ? Icons.star : Icons.star_border,
            size: 12,
            color: Colors.amber,
          ),
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplier: s)),
      ),
    );
  }

  Widget _buildOrderTile(BuildContext context, PurchaseOrder o) {
    final total = o.lines.fold(0.0, (sum, l) => sum + l.lineTotal);
    final statusColor = _orderStatusColor(o.status);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.12),
        child: Icon(_orderStatusIcon(o.status), size: 18, color: statusColor),
      ),
      title: Text(
        o.orderNumber,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${o.supplierName} • ${DateFormat('dd MMM yyyy').format(o.orderDate)}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatCurrency(total),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              o.status.label,
              style: TextStyle(
                fontSize: 9,
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PurchaseOrderDetailScreen(order: o)),
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
}
