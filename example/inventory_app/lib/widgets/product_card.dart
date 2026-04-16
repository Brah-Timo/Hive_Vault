// example/inventory_app/lib/widgets/product_card.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reusable product card with stock status badge, pricing info, quick actions,
// and swipe-to-delete via flutter_slidable.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/product.dart';
import '../utils/formatters.dart';
import '../theme/app_theme.dart';
import 'stock_status_badge.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final String? categoryName;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAddStock;
  final VoidCallback? onDelete;

  const ProductCard({
    super.key,
    required this.product,
    this.categoryName,
    this.onTap,
    this.onEdit,
    this.onAddStock,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ─────────────────────────────────────────────
              Row(
                children: [
                  _buildProductAvatar(theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${product.sku}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                        if (product.location != null) ...[
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 10, color: Colors.grey.shade400),
                              const SizedBox(width: 2),
                              Text(
                                product.location!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade400,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  StockStatusBadge(product: product, compact: true),
                ],
              ),

              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 10),

              // ── Metrics row ────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _metricItem(
                    context,
                    label: 'Stock',
                    value: formatStock(product.currentStock, product.unit.name),
                    valueColor: product.isOutOfStock
                        ? AppTheme.errorColor
                        : product.isLowStock
                            ? AppTheme.warningColor
                            : AppTheme.successColor,
                  ),
                  _metricItem(
                    context,
                    label: 'Min',
                    value: formatNumber(product.minimumStock),
                  ),
                  _metricItem(
                    context,
                    label: 'Cost',
                    value: formatCurrency(product.costPrice),
                  ),
                  _metricItem(
                    context,
                    label: 'Price',
                    value: formatCurrency(product.sellingPrice),
                    valueColor: Colors.green.shade700,
                  ),
                ],
              ),

              // ── Tags row ───────────────────────────────────────────────
              if (categoryName != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _tag(
                      icon: Icons.folder_outlined,
                      label: categoryName!,
                      color: AppTheme.primaryColor,
                    ),
                    if (product.location != null)
                      _tag(
                        icon: Icons.location_on_outlined,
                        label: product.location!,
                        color: Colors.blueGrey,
                      ),
                    if (product.status != ProductStatus.active)
                      _tag(
                        icon: Icons.info_outline,
                        label: product.status.name,
                        color: Colors.grey,
                      ),
                  ],
                ),
              ],

              // ── Action row ─────────────────────────────────────────────
              if (onAddStock != null || onEdit != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onAddStock != null)
                      _actionBtn(
                        icon: Icons.add_circle_outline,
                        label: 'Add Stock',
                        onTap: onAddStock!,
                      ),
                    if (onEdit != null)
                      _actionBtn(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: onEdit!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Wrap with Slidable only when delete callback is provided
    if (onDelete != null) {
      return Slidable(
        key: ValueKey(product.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.22,
          children: [
            SlidableAction(
              onPressed: (_) => onDelete!(),
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'Delete',
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(12)),
            ),
          ],
        ),
        child: card,
      );
    }

    return card;
  }

  Widget _buildProductAvatar(ThemeData theme) {
    final color = product.isOutOfStock
        ? AppTheme.errorColor
        : product.isLowStock
            ? AppTheme.warningColor
            : theme.colorScheme.primary;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withAlpha(26), // ~10% opacity
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.inventory_2,
        color: color,
        size: 22,
      ),
    );
  }

  Widget _metricItem(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: valueColor,
                ),
          ),
        ],
      );

  Widget _tag({
    required IconData icon,
    required String label,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          visualDensity: VisualDensity.compact,
          foregroundColor: AppTheme.primaryColor,
        ),
      );
}
