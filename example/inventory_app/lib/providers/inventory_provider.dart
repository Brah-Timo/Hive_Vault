// example/inventory_app/lib/providers/inventory_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Central ChangeNotifier for the Inventory Management System.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../models/purchase_order.dart';
import '../models/stock_alert.dart';
import '../models/inventory_report.dart';
import '../repositories/product_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/stock_movement_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/purchase_order_repository.dart';
import '../repositories/alert_repository.dart';
import '../services/stock_service.dart';
import '../services/report_service.dart';
import '../services/notification_service.dart';

class InventoryProvider extends ChangeNotifier {
  final ProductRepository _productRepo;
  final CategoryRepository _categoryRepo;
  final StockMovementRepository _movementRepo;
  final SupplierRepository _supplierRepo;
  final PurchaseOrderRepository _orderRepo;
  final AlertRepository _alertRepo;
  final StockService _stockService;
  final ReportService _reportService;
  final NotificationService _notificationService;
  final _uuid = const Uuid();

  InventoryProvider({
    required ProductRepository productRepo,
    required CategoryRepository categoryRepo,
    required StockMovementRepository movementRepo,
    required SupplierRepository supplierRepo,
    required PurchaseOrderRepository orderRepo,
    required AlertRepository alertRepo,
    required StockService stockService,
    required ReportService reportService,
    required NotificationService notificationService,
  })  : _productRepo = productRepo,
        _categoryRepo = categoryRepo,
        _movementRepo = movementRepo,
        _supplierRepo = supplierRepo,
        _orderRepo = orderRepo,
        _alertRepo = alertRepo,
        _stockService = stockService,
        _reportService = reportService,
        _notificationService = notificationService;

  // ── State ─────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;

  List<Product> _products = [];
  List<ProductCategory> _categories = [];
  List<StockMovement> _movements = [];
  List<Supplier> _suppliers = [];
  List<PurchaseOrder> _orders = [];
  List<StockAlert> _alerts = [];
  InventorySummary _summary = InventorySummary.empty;

  String _productSearch = '';
  String? _selectedCategoryFilter;
  ProductStatus? _statusFilter;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Product> get products => _filteredProducts;
  List<Product> get allProducts => _products;
  List<ProductCategory> get categories => _categories;
  List<StockMovement> get movements => _movements;
  List<Supplier> get suppliers => _suppliers;
  List<PurchaseOrder> get orders => _orders;
  List<StockAlert> get alerts => _alerts;
  List<StockAlert> get activeAlerts =>
      _alerts.where((a) => !a.isDismissed).toList();
  List<StockAlert> get unreadAlerts =>
      _alerts.where((a) => !a.isRead && !a.isDismissed).toList();
  InventorySummary get summary => _summary;

  int get unreadAlertCount => unreadAlerts.length;
  int get pendingOrderCount => _orders
      .where((o) =>
          o.status != PurchaseOrderStatus.fullyReceived &&
          o.status != PurchaseOrderStatus.cancelled)
      .length;

  String get productSearch => _productSearch;
  String? get selectedCategoryFilter => _selectedCategoryFilter;
  ProductStatus? get statusFilter => _statusFilter;

  List<Product> get _filteredProducts {
    var result = _products;
    if (_productSearch.isNotEmpty) {
      final q = _productSearch.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q))
          .toList();
    }
    if (_selectedCategoryFilter != null) {
      result =
          result.where((p) => p.categoryId == _selectedCategoryFilter).toList();
    }
    if (_statusFilter != null) {
      result = result.where((p) => p.status == _statusFilter).toList();
    }
    return result;
  }

  ProductCategory? categoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Supplier? supplierById(String id) {
    try {
      return _suppliers.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await _categoryRepo.ensureDefaultsExist();
    await loadAll();
  }

  Future<void> loadAll() async {
    _setLoading(true);
    try {
      await Future.wait([
        _loadProducts(),
        _loadCategories(),
        _loadMovements(),
        _loadSuppliers(),
        _loadOrders(),
        _loadAlerts(),
      ]);
      await _refreshSummary();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadProducts() async {
    _products = await _productRepo.getAllProducts();
  }

  Future<void> _loadCategories() async {
    _categories = await _categoryRepo.getAllCategories();
  }

  Future<void> _loadMovements() async {
    _movements = await _movementRepo.getRecentMovements(limit: 100);
  }

  Future<void> _loadSuppliers() async {
    _suppliers = await _supplierRepo.getAllSuppliers();
  }

  Future<void> _loadOrders() async {
    _orders = await _orderRepo.getAllOrders();
  }

  Future<void> _loadAlerts() async {
    _alerts = await _alertRepo.getAllAlerts();
  }

  Future<void> _refreshSummary() async {
    _summary = await _reportService.getDashboardSummary();
  }

  // ── Product operations ────────────────────────────────────────────────────

  Future<bool> saveProduct(Product product) async {
    try {
      await _productRepo.saveProduct(product);
      await _loadProducts();
      await _refreshSummary();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteProduct(String id) async {
    try {
      await _productRepo.deleteProduct(id);
      await _loadProducts();
      await _refreshSummary();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<Product?> getProductByBarcode(String barcode) =>
      _productRepo.getByBarcode(barcode);

  // ── Stock movements ───────────────────────────────────────────────────────

  Future<bool> recordMovement({
    required String productId,
    required MovementType type,
    required double quantity,
    String? reference,
    String? notes,
    String? userId = 'current_user',
  }) async {
    try {
      await _stockService.recordMovement(
        productId: productId,
        type: type,
        quantity: quantity,
        reference: reference,
        notes: notes,
        userId: userId,
      );
      await _loadProducts();
      await _loadMovements();
      await _loadAlerts();
      await _refreshSummary();

      // Show local notification for critical alerts
      final newAlerts = await _alertRepo.getUnreadAlerts();
      for (final alert in newAlerts.take(3)) {
        await _notificationService.showAlertNotification(alert);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Categories ────────────────────────────────────────────────────────────

  Future<bool> saveCategory(ProductCategory category) async {
    try {
      await _categoryRepo.save(category);
      await _loadCategories();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    try {
      await _categoryRepo.delete('category:$id');
      await _loadCategories();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Suppliers ─────────────────────────────────────────────────────────────

  Future<bool> saveSupplier(Supplier supplier) async {
    try {
      await _supplierRepo.save(supplier);
      await _loadSuppliers();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSupplier(String id) async {
    try {
      await _supplierRepo.delete('supplier:$id');
      await _loadSuppliers();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Purchase Orders ───────────────────────────────────────────────────────

  Future<bool> createPurchaseOrder(PurchaseOrder order) async {
    try {
      await _orderRepo.save(order);
      await _loadOrders();
      await _refreshSummary();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateOrderStatus(
      String orderId, PurchaseOrderStatus status) async {
    try {
      final order = await _orderRepo.getById(orderId);
      if (order == null) return false;
      await _orderRepo.save(order.copyWith(status: status));
      await _loadOrders();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Receive goods from a purchase order (updates stock for each line).
  Future<bool> receiveOrder(
      PurchaseOrder order, Map<String, double> receivedQtys) async {
    try {
      final updatedLines = order.lines.map((line) {
        final qty = receivedQtys[line.productId] ?? 0;
        return PurchaseOrderLine(
          productId: line.productId,
          productName: line.productName,
          sku: line.sku,
          orderedQty: line.orderedQty,
          receivedQty: line.receivedQty + qty,
          unitCost: line.unitCost,
          notes: line.notes,
        );
      }).toList();

      // Check if fully received
      final allReceived = updatedLines.every((l) => l.isFullyReceived);
      final newStatus = allReceived
          ? PurchaseOrderStatus.fullyReceived
          : PurchaseOrderStatus.partiallyReceived;

      // Update stock for each line
      for (final line in updatedLines) {
        final received = receivedQtys[line.productId] ?? 0;
        if (received > 0) {
          await _stockService.receiveStock(
            productId: line.productId,
            quantity: received,
            reference: order.orderNumber,
            notes: 'PO Receipt: ${order.orderNumber}',
            userId: 'current_user',
          );
        }
      }

      await _orderRepo.save(order.copyWith(
        status: newStatus,
        lines: updatedLines,
        receivedDate: DateTime.now(),
      ));

      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Auto-create purchase orders for all products at reorder point.
  Future<int> createReorderRequests() async {
    int created = 0;
    final products = await _productRepo.getAllProducts();
    final reorderProducts = products
        .where((p) =>
            p.status == ProductStatus.active &&
            p.needsReorder &&
            p.supplierId != null)
        .toList();

    // Group by supplier
    final bySupplier = <String, List<Product>>{};
    for (final p in reorderProducts) {
      bySupplier.putIfAbsent(p.supplierId!, () => []).add(p);
    }

    for (final entry in bySupplier.entries) {
      final supplier = await _supplierRepo.getById(entry.key);
      if (supplier == null) continue;

      final orderNum = await _orderRepo.generateOrderNumber();
      final order = PurchaseOrder(
        id: _uuid.v4(),
        orderNumber: orderNum,
        supplierId: supplier.id,
        supplierName: supplier.name,
        status: PurchaseOrderStatus.draft,
        lines: entry.value
            .map((p) => PurchaseOrderLine(
                  productId: p.id,
                  productName: p.name,
                  sku: p.sku,
                  orderedQty: p.reorderQty,
                  unitCost: p.costPrice,
                ))
            .toList(),
        notes: 'Auto-generated reorder request',
        createdBy: 'system',
      );

      await _orderRepo.save(order);
      created++;
    }

    if (created > 0) {
      await _loadOrders();
      notifyListeners();
    }
    return created;
  }

  // ── Alerts ────────────────────────────────────────────────────────────────

  Future<void> markAllAlertsRead() async {
    await _alertRepo.markAllRead();
    await _loadAlerts();
    await _refreshSummary();
    notifyListeners();
  }

  Future<void> dismissAlert(String alertId) async {
    await _alertRepo.dismissAlert(alertId);
    await _loadAlerts();
    await _refreshSummary();
    notifyListeners();
  }

  Future<int> runAlertScan() async {
    final count = await _stockService.runAlertScan();
    await _loadAlerts();
    await _refreshSummary();
    if (count > 0) {
      await _notificationService.showBatchAlertSummary(count);
    }
    notifyListeners();
    return count;
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  void setProductSearch(String query) {
    _productSearch = query;
    notifyListeners();
  }

  void setCategoryFilter(String? categoryId) {
    _selectedCategoryFilter = categoryId;
    notifyListeners();
  }

  void setStatusFilter(ProductStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void clearFilters() {
    _productSearch = '';
    _selectedCategoryFilter = null;
    _statusFilter = null;
    notifyListeners();
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<List<LowStockItem>> getLowStockReport() =>
      _reportService.getLowStockReport();

  Future<List<ValuationItem>> getValuationReport() =>
      _reportService.getValuationReport();

  Future<List<StockMovement>> getMovementReport({
    DateTime? from,
    DateTime? to,
    String? productId,
  }) =>
      _reportService.getMovementReport(
          from: from, to: to, productId: productId);

  Future<List<LowStockItem>> getReorderReport() =>
      _reportService.getReorderReport();

  // ── Demo data ─────────────────────────────────────────────────────────────

  Future<void> seedDemoData() async {
    _setLoading(true);
    try {
      final supplier1 = Supplier(
        id: _uuid.v4(),
        name: 'TechParts Ltd',
        contactName: 'John Smith',
        email: 'orders@techparts.com',
        phone: '+1-555-0100',
        defaultLeadTimeDays: 5,
        rating: 4.5,
      );
      final supplier2 = Supplier(
        id: _uuid.v4(),
        name: 'Global Supply Co.',
        contactName: 'Jane Doe',
        email: 'procurement@globalsupply.com',
        phone: '+1-555-0200',
        defaultLeadTimeDays: 7,
        rating: 4.0,
      );

      await _supplierRepo.save(supplier1);
      await _supplierRepo.save(supplier2);

      final sampleProducts = [
        Product(
          id: _uuid.v4(),
          name: 'Wireless Mouse',
          sku: 'ELC-001',
          barcode: '1234567890123',
          categoryId: 'cat_electronics',
          supplierId: supplier1.id,
          description: 'Ergonomic wireless mouse with USB receiver',
          currentStock: 45,
          minimumStock: 10,
          reorderPoint: 15,
          reorderQty: 100,
          maximumStock: 500,
          costPrice: 12.50,
          sellingPrice: 24.99,
          unit: UnitOfMeasure.pieces,
          location: 'A-01-03',
        ),
        Product(
          id: _uuid.v4(),
          name: 'USB-C Hub 7-port',
          sku: 'ELC-002',
          barcode: '2345678901234',
          categoryId: 'cat_electronics',
          supplierId: supplier1.id,
          description: '7-port USB-C hub with HDMI output',
          currentStock: 8,
          minimumStock: 10,
          reorderPoint: 15,
          reorderQty: 50,
          maximumStock: 200,
          costPrice: 28.00,
          sellingPrice: 54.99,
          unit: UnitOfMeasure.pieces,
          location: 'A-01-04',
        ),
        Product(
          id: _uuid.v4(),
          name: 'A4 Copy Paper (500 sheets)',
          sku: 'OFF-001',
          barcode: '3456789012345',
          categoryId: 'cat_office',
          supplierId: supplier2.id,
          description: '80gsm A4 copy paper, 500 sheets per ream',
          currentStock: 120,
          minimumStock: 20,
          reorderPoint: 30,
          reorderQty: 200,
          maximumStock: 1000,
          costPrice: 4.20,
          sellingPrice: 7.99,
          unit: UnitOfMeasure.boxes,
          location: 'B-02-01',
        ),
        Product(
          id: _uuid.v4(),
          name: 'Ballpoint Pens (12-pack)',
          sku: 'OFF-002',
          barcode: '4567890123456',
          categoryId: 'cat_office',
          supplierId: supplier2.id,
          description: 'Blue ink ballpoint pens, pack of 12',
          currentStock: 0,
          minimumStock: 15,
          reorderPoint: 20,
          reorderQty: 100,
          maximumStock: 500,
          costPrice: 2.80,
          sellingPrice: 5.49,
          unit: UnitOfMeasure.pieces,
          location: 'B-02-02',
        ),
        Product(
          id: _uuid.v4(),
          name: 'Mechanical Keyboard',
          sku: 'ELC-003',
          barcode: '5678901234567',
          categoryId: 'cat_electronics',
          supplierId: supplier1.id,
          description: 'TKL mechanical keyboard, Cherry MX Blue switches',
          currentStock: 22,
          minimumStock: 5,
          reorderPoint: 8,
          reorderQty: 30,
          maximumStock: 150,
          costPrice: 65.00,
          sellingPrice: 129.99,
          unit: UnitOfMeasure.pieces,
          location: 'A-02-01',
        ),
      ];

      for (final p in sampleProducts) {
        await _productRepo.saveProduct(p);
      }

      await loadAll();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Persist user preferences to the alert vault (re-used for settings).
  Future<void> saveSettings(Map<String, dynamic> prefs) async {
    try {
      for (final entry in prefs.entries) {
        await _alertRepo.saveRaw(
            'setting:${entry.key}', entry.value.toString());
      }
    } catch (_) {}
  }

  /// Load user preferences from the alert vault.
  Future<Map<String, dynamic>> loadSettings() async {
    final Map<String, dynamic> result = {};
    try {
      final keys = [
        'lowStockNotif',
        'outOfStockNotif',
        'reorderNotif',
        'orderStatusNotif',
        'currency',
        'showCostPrice',
        'compactMode',
      ];
      for (final k in keys) {
        final raw = await _alertRepo.getRaw('setting:$k');
        if (raw != null) {
          if (raw == 'true' || raw == 'false') {
            result[k] = raw == 'true';
          } else {
            result[k] = raw;
          }
        }
      }
    } catch (_) {}
    return result;
  }

  // ── Inventory Count ───────────────────────────────────────────────────────

  /// Apply a stocktake adjustment — sets stock to [physicalCount].
  Future<bool> adjustStockToCount({
    required String productId,
    required double physicalCount,
    String notes = 'Stocktake adjustment',
  }) async {
    try {
      final products = await _productRepo.getAllProducts();
      final product = products.where((p) => p.id == productId).firstOrNull;
      if (product == null) return false;

      final variance = physicalCount - product.currentStock;
      if (variance.abs() < 0.001) return true; // no change needed

      return await recordMovement(
        productId: productId,
        type: MovementType.adjustment,
        quantity: variance.abs(),
        notes: notes,
        userId: 'stocktake',
        reference: 'STKTK-${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Clear All Data ────────────────────────────────────────────────────────

  Future<void> clearAllData() async {
    _setLoading(true);
    try {
      await _productRepo.deleteAll();
      await _movementRepo.deleteAll();
      await _alertRepo.deleteAll();
      await _orderRepo.deleteAll();
      await _supplierRepo.deleteAll();
      _products = [];
      _movements = [];
      _alerts = [];
      _orders = [];
      _suppliers = [];
      _categories = [];
      _summary = InventorySummary.empty;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  List<StockMovement> movementsForProduct(String productId) =>
      _movements.where((m) => m.productId == productId).toList();
}
