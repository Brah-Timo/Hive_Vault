// example/inventory_app/lib/models/inventory_report.dart
// ─────────────────────────────────────────────────────────────────────────────
// Report model types: InventorySummary, LowStockItem, ValuationItem.
// ─────────────────────────────────────────────────────────────────────────────

enum ReportType {
  stockSummary,
  stockMovements,
  lowStockReport,
  valuationReport,
  supplierReport,
  categoryReport,
  reorderReport,
}

extension ReportTypeX on ReportType {
  String get label => switch (this) {
        ReportType.stockSummary => 'Stock Summary',
        ReportType.stockMovements => 'Stock Movements',
        ReportType.lowStockReport => 'Low Stock Report',
        ReportType.valuationReport => 'Valuation Report',
        ReportType.supplierReport => 'Supplier Report',
        ReportType.categoryReport => 'Category Report',
        ReportType.reorderReport => 'Reorder Report',
      };

  String get description => switch (this) {
        ReportType.stockSummary =>
          'Overview of current inventory levels across all products',
        ReportType.stockMovements =>
          'Detailed log of all stock in/out movements',
        ReportType.lowStockReport =>
          'Products below minimum stock thresholds',
        ReportType.valuationReport =>
          'Total inventory value by cost and selling price',
        ReportType.supplierReport =>
          'Purchase history and performance by supplier',
        ReportType.categoryReport =>
          'Stock distribution and value by category',
        ReportType.reorderReport =>
          'Products requiring reorder based on current stock',
      };
}

/// Summary statistics shown on the dashboard.
///
/// [generatedAt] is a regular [DateTime] field (not const) so we avoid the
/// old `_EpochDate` workaround.  The factory [InventorySummary.empty] returns
/// a zero-value instance with `generatedAt = DateTime(2000)`.
class InventorySummary {
  final int totalProducts;
  final int activeProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int overstockCount;
  final double totalCostValue;
  final double totalSellingValue;
  final double potentialProfit;
  final int pendingOrders;
  final int unreadAlerts;
  final Map<String, int> stockByCategory;
  final Map<String, double> valueByCategory;
  final DateTime generatedAt;

  const InventorySummary({
    required this.totalProducts,
    required this.activeProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.overstockCount,
    required this.totalCostValue,
    required this.totalSellingValue,
    required this.potentialProfit,
    required this.pendingOrders,
    required this.unreadAlerts,
    required this.stockByCategory,
    required this.valueByCategory,
    required this.generatedAt,
  });

  /// Zero-value sentinel used before the first real summary is loaded.
  static InventorySummary get empty => InventorySummary(
        totalProducts: 0,
        activeProducts: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        overstockCount: 0,
        totalCostValue: 0,
        totalSellingValue: 0,
        potentialProfit: 0,
        pendingOrders: 0,
        unreadAlerts: 0,
        stockByCategory: const {},
        valueByCategory: const {},
        generatedAt: DateTime(2000),
      );
}

/// Low-stock report row.
class LowStockItem {
  final String productId;
  final String name;
  final String sku;
  final String categoryName;
  final double currentStock;
  final double minimumStock;
  final double reorderPoint;
  final double reorderQty;
  final String? supplierName;
  final double costPrice;

  const LowStockItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.categoryName,
    required this.currentStock,
    required this.minimumStock,
    required this.reorderPoint,
    required this.reorderQty,
    this.supplierName,
    required this.costPrice,
  });

  double get deficit => (minimumStock - currentStock).clamp(0, double.infinity);
  bool get isCritical => currentStock <= 0;
}

/// Valuation row per product.
class ValuationItem {
  final String productId;
  final String name;
  final String sku;
  final String categoryName;
  final double quantity;
  final double costPrice;
  final double sellingPrice;
  final double costValue;
  final double sellingValue;

  const ValuationItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.categoryName,
    required this.quantity,
    required this.costPrice,
    required this.sellingPrice,
    required this.costValue,
    required this.sellingValue,
  });

  double get grossProfit => sellingValue - costValue;
  double get margin =>
      sellingValue > 0 ? (grossProfit / sellingValue) * 100 : 0;
}
