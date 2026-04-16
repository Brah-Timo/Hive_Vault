// example/inventory_app/lib/screens/products/product_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../providers/inventory_provider.dart';
import '../../utils/formatters.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stock_status_badge.dart';
import '../stock/stock_movement_form_screen.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        // Get latest product data
        final current =
            prov.allProducts.where((p) => p.id == product.id).firstOrNull ??
                product;
        final category = prov.categoryById(current.categoryId);
        final supplier = current.supplierId != null
            ? prov.supplierById(current.supplierId!)
            : null;
        final movements = prov.movementsForProduct(current.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProductFormScreen(product: current)),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusHeader(context, current),
                const SizedBox(height: 12),
                _buildStockSection(context, current),
                const SizedBox(height: 12),
                _buildPricingSection(context, current),
                const SizedBox(height: 12),
                _buildInfoSection(
                    context, current, category?.name, supplier?.name),
                const SizedBox(height: 12),
                _buildBarcodeSection(context, current),
                const SizedBox(height: 12),
                _buildMovementsSection(context, movements),
              ],
            ),
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'out',
                onPressed: () => _recordMovement(context, current, false),
                backgroundColor: Colors.red.shade700,
                child: const Icon(Icons.remove),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'in',
                onPressed: () => _recordMovement(context, current, true),
                child: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader(BuildContext context, Product p) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.inventory_2,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text('SKU: ${p.sku}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 6),
                  StockStatusBadge(product: p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockSection(BuildContext context, Product p) {
    return _section(
      context,
      title: 'Stock Levels',
      icon: Icons.bar_chart_outlined,
      children: [
        _stockBar(context, 'Current Stock', p.currentStock, p.maximumStock,
            _stockColor(p)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stockStat('Current', '${p.currentStock.toInt()}', _stockColor(p)),
            _stockStat('Minimum', '${p.minimumStock.toInt()}', Colors.orange),
            _stockStat('Reorder', '${p.reorderPoint.toInt()}', Colors.blue),
            _stockStat('Maximum', '${p.maximumStock.toInt()}', Colors.green),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Reorder Qty: ${p.reorderQty.toInt()} ${p.unit.name}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (p.location != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Location: ${p.location}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
      ],
    );
  }

  Color _stockColor(Product p) {
    if (p.isOutOfStock) return AppTheme.outOfStockColor;
    if (p.isLowStock) return AppTheme.lowStockColor;
    return AppTheme.inStockColor;
  }

  Widget _stockBar(BuildContext context, String label, double current,
      double max, Color color) {
    final pct = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              '${current.toInt()} / ${max.toInt()}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _stockStat(String label, String value, Color color) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 18),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Widget _buildPricingSection(BuildContext context, Product p) {
    return _section(
      context,
      title: 'Pricing',
      icon: Icons.attach_money,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _priceTile(
                'Cost Price', formatCurrency(p.costPrice), Colors.red.shade700),
            _priceTile('Selling Price', formatCurrency(p.sellingPrice),
                Colors.green.shade700),
            _priceTile('Margin', formatPercent(p.margin), Colors.blue.shade700),
          ],
        ),
        const Divider(),
        _infoRow('Stock Value (Cost)', formatCurrency(p.stockValue)),
        _infoRow('Stock Value (Sell)',
            formatCurrency(p.currentStock * p.sellingPrice)),
      ],
    );
  }

  Widget _priceTile(String label, String value, Color color) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 16),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  Widget _buildInfoSection(BuildContext context, Product p,
      String? categoryName, String? supplierName) {
    return _section(
      context,
      title: 'Product Information',
      icon: Icons.info_outline,
      children: [
        if (p.description != null && p.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(p.description!,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        _infoRow('Category', categoryName ?? 'Unknown'),
        _infoRow('Supplier', supplierName ?? 'Not set'),
        _infoRow('Unit', p.unit.name),
        _infoRow('Status', p.status.name.toUpperCase()),
        _infoRow('Barcode', p.barcode),
        _infoRow('Created', formatDate(p.createdAt)),
        _infoRow('Last Updated', formatDateTime(p.updatedAt)),
      ],
    );
  }

  Widget _buildBarcodeSection(BuildContext context, Product p) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_outlined, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Barcode',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: p.barcode.isEmpty ? p.sku : p.barcode,
                width: 200,
                height: 70,
                drawText: true,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementsSection(BuildContext context, List movements) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Recent Movements',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No movements recorded.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...movements.take(10).map((m) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: m.type.isPositive
                        ? Colors.green.withOpacity(0.12)
                        : Colors.red.withOpacity(0.12),
                    child: Icon(
                      m.type.isPositive
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 14,
                      color: m.type.isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(
                    m.type.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${formatDateTime(m.createdAt)}${m.reference != null ? ' · ${m.reference}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${m.type.isPositive ? '+' : '-'}${m.quantity.toInt()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: m.type.isPositive ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        '→ ${m.stockAfter.toInt()}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) =>
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  void _recordMovement(BuildContext context, Product p, bool isIn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StockMovementFormSheet(product: p, preferIn: isIn),
    );
  }
}
