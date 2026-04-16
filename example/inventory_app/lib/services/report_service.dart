// example/inventory_app/lib/services/report_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Generates inventory reports and dashboard summary.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/product.dart';
import '../models/inventory_report.dart';
import '../models/stock_movement.dart';
import '../repositories/product_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/stock_movement_repository.dart';
import '../repositories/purchase_order_repository.dart';
import '../repositories/alert_repository.dart';
import '../repositories/supplier_repository.dart';

class ReportService {
  final ProductRepository _productRepo;
  final CategoryRepository _categoryRepo;
  final StockMovementRepository _movementRepo;
  final PurchaseOrderRepository _orderRepo;
  final AlertRepository _alertRepo;
  final SupplierRepository _supplierRepo;

  ReportService({
    required ProductRepository productRepo,
    required CategoryRepository categoryRepo,
    required StockMovementRepository movementRepo,
    required PurchaseOrderRepository orderRepo,
    required AlertRepository alertRepo,
    required SupplierRepository supplierRepo,
  })  : _productRepo = productRepo,
        _categoryRepo = categoryRepo,
        _movementRepo = movementRepo,
        _orderRepo = orderRepo,
        _alertRepo = alertRepo,
        _supplierRepo = supplierRepo;

  // ── Dashboard summary ─────────────────────────────────────────────────────

  Future<InventorySummary> getDashboardSummary() async {
    final products = await _productRepo.getAllProducts();
    final activeProducts =
        products.where((p) => p.status == ProductStatus.active).toList();
    final categories = await _categoryRepo.getAllCategories();
    final pendingOrders = await _orderRepo.getPendingOrders();
    final unreadAlerts = await _alertRepo.getUnreadAlerts();

    // Build category maps
    final catNameMap = {for (final c in categories) c.id: c.name};
    final stockByCategory = <String, int>{};
    final valueByCategory = <String, double>{};

    double totalCostValue = 0;
    double totalSellingValue = 0;

    for (final product in activeProducts) {
      totalCostValue += product.stockValue;
      totalSellingValue += product.currentStock * product.sellingPrice;

      final catName = catNameMap[product.categoryId] ?? 'Uncategorised';
      stockByCategory[catName] = (stockByCategory[catName] ?? 0) + 1;
      valueByCategory[catName] =
          (valueByCategory[catName] ?? 0) + product.stockValue;
    }

    return InventorySummary(
      totalProducts: products.length,
      activeProducts: activeProducts.length,
      lowStockCount: activeProducts.where((p) => p.isLowStock).length,
      outOfStockCount: activeProducts.where((p) => p.isOutOfStock).length,
      overstockCount:
          activeProducts.where((p) => p.currentStock >= p.maximumStock).length,
      totalCostValue: totalCostValue,
      totalSellingValue: totalSellingValue,
      potentialProfit: totalSellingValue - totalCostValue,
      pendingOrders: pendingOrders.length,
      unreadAlerts: unreadAlerts.length,
      stockByCategory: stockByCategory,
      valueByCategory: valueByCategory,
      generatedAt: DateTime.now(),
    );
  }

  // ── Low stock report ──────────────────────────────────────────────────────

  Future<List<LowStockItem>> getLowStockReport() async {
    final products = await _productRepo.getLowStockProducts();
    final categories = await _categoryRepo.getAllCategories();
    final suppliers = await _supplierRepo.getAllSuppliers();
    final catMap = {for (final c in categories) c.id: c.name};
    final supMap = {for (final s in suppliers) s.id: s.name};

    return products
        .map((p) => LowStockItem(
              productId: p.id,
              name: p.name,
              sku: p.sku,
              categoryName: catMap[p.categoryId] ?? 'Unknown',
              currentStock: p.currentStock,
              minimumStock: p.minimumStock,
              reorderPoint: p.reorderPoint,
              reorderQty: p.reorderQty,
              supplierName: p.supplierId != null ? supMap[p.supplierId] : null,
              costPrice: p.costPrice,
            ))
        .toList()
      ..sort((a, b) => a.currentStock.compareTo(b.currentStock));
  }

  // ── Valuation report ──────────────────────────────────────────────────────

  Future<List<ValuationItem>> getValuationReport() async {
    final products = await _productRepo.getAllProducts();
    final categories = await _categoryRepo.getAllCategories();
    final catMap = {for (final c in categories) c.id: c.name};

    return products
        .where((p) => p.status == ProductStatus.active)
        .map((p) => ValuationItem(
              productId: p.id,
              name: p.name,
              sku: p.sku,
              categoryName: catMap[p.categoryId] ?? 'Unknown',
              quantity: p.currentStock,
              costPrice: p.costPrice,
              sellingPrice: p.sellingPrice,
              costValue: p.currentStock * p.costPrice,
              sellingValue: p.currentStock * p.sellingPrice,
            ))
        .toList()
      ..sort((a, b) => b.costValue.compareTo(a.costValue));
  }

  // ── Movement report ───────────────────────────────────────────────────────

  Future<List<StockMovement>> getMovementReport({
    DateTime? from,
    DateTime? to,
    String? productId,
    MovementType? type,
  }) async {
    final from_ = from ?? DateTime.now().subtract(const Duration(days: 30));
    final to_ = to ?? DateTime.now();
    final movements = await _movementRepo.getMovementsInRange(from_, to_);
    return movements
        .where((m) =>
            (productId == null || m.productId == productId) &&
            (type == null || m.type == type))
        .toList();
  }

  // ── Reorder report ────────────────────────────────────────────────────────

  Future<List<LowStockItem>> getReorderReport() async {
    final products = await _productRepo.getAllProducts();
    final activeProducts = products
        .where((p) => p.status == ProductStatus.active && p.needsReorder)
        .toList();
    final categories = await _categoryRepo.getAllCategories();
    final suppliers = await _supplierRepo.getAllSuppliers();
    final catMap = {for (final c in categories) c.id: c.name};
    final supMap = {for (final s in suppliers) s.id: s.name};

    return activeProducts
        .map((p) => LowStockItem(
              productId: p.id,
              name: p.name,
              sku: p.sku,
              categoryName: catMap[p.categoryId] ?? 'Unknown',
              currentStock: p.currentStock,
              minimumStock: p.minimumStock,
              reorderPoint: p.reorderPoint,
              reorderQty: p.reorderQty,
              supplierName: p.supplierId != null ? supMap[p.supplierId] : null,
              costPrice: p.costPrice,
            ))
        .toList();
  }

  // ── Category summary ──────────────────────────────────────────────────────

  Future<Map<String, Map<String, dynamic>>> getCategoryReport() async {
    final products = await _productRepo.getAllProducts();
    final categories = await _categoryRepo.getAllCategories();
    final catMap = {for (final c in categories) c.id: c};

    final report = <String, Map<String, dynamic>>{};
    for (final cat in categories) {
      report[cat.id] = {
        'name': cat.name,
        'productCount': 0,
        'totalCostValue': 0.0,
        'totalSellingValue': 0.0,
        'lowStockCount': 0,
        'outOfStockCount': 0,
      };
    }

    for (final p in products) {
      if (!report.containsKey(p.categoryId)) {
        report[p.categoryId] = {
          'name': catMap[p.categoryId]?.name ?? 'Unknown',
          'productCount': 0,
          'totalCostValue': 0.0,
          'totalSellingValue': 0.0,
          'lowStockCount': 0,
          'outOfStockCount': 0,
        };
      }
      final entry = report[p.categoryId]!;
      entry['productCount'] = (entry['productCount'] as int) + 1;
      entry['totalCostValue'] =
          (entry['totalCostValue'] as double) + p.stockValue;
      entry['totalSellingValue'] = (entry['totalSellingValue'] as double) +
          p.currentStock * p.sellingPrice;
      if (p.isLowStock) {
        entry['lowStockCount'] = (entry['lowStockCount'] as int) + 1;
      }
      if (p.isOutOfStock) {
        entry['outOfStockCount'] = (entry['outOfStockCount'] as int) + 1;
      }
    }

    return report;
  }
}
