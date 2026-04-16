// example/inventory_app/lib/widgets/stock_status_badge.dart
// ─────────────────────────────────────────────────────────────────────────────
// Coloured chip that shows the current stock status of a product.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

class StockStatusBadge extends StatelessWidget {
  final Product product;

  /// When [compact] is true, uses smaller padding and font.
  final bool compact;

  const StockStatusBadge({
    super.key,
    required this.product,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.stockStatusColor(product.stockStatusLabel);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical:  compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color:  color.withAlpha(31),  // ~12%
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)), // ~30%
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            product.stockStatusLabel,
            style: TextStyle(
              color:      color,
              fontSize:   compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
