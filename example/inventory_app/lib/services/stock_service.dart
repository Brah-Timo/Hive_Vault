// example/inventory_app/lib/services/stock_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Business logic for all stock movement operations.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';
import '../models/stock_alert.dart';
import '../repositories/product_repository.dart';
import '../repositories/stock_movement_repository.dart';
import '../repositories/alert_repository.dart';

class StockService {
  final ProductRepository _productRepo;
  final StockMovementRepository _movementRepo;
  final AlertRepository _alertRepo;
  final _uuid = const Uuid();

  StockService({
    required ProductRepository productRepo,
    required StockMovementRepository movementRepo,
    required AlertRepository alertRepo,
  })  : _productRepo = productRepo,
        _movementRepo = movementRepo,
        _alertRepo = alertRepo;

  // ── Core movement recording ───────────────────────────────────────────────

  /// Records a stock movement and updates the product's current stock.
  Future<StockMovement> recordMovement({
    required String productId,
    required MovementType type,
    required double quantity,
    String? reference,
    String? notes,
    String? userId,
    String? locationFrom,
    String? locationTo,
    String? orderId,
  }) async {
    if (quantity <= 0) throw ArgumentError('Quantity must be positive');

    final product = await _productRepo.getById(productId);
    if (product == null) throw StateError('Product $productId not found');

    final stockBefore = product.currentStock;
    final delta = type.isPositive ? quantity : -quantity;
    final stockAfter = (stockBefore + delta).clamp(0.0, double.infinity);

    final movement = StockMovement(
      id: _uuid.v4(),
      productId: productId,
      type: type,
      quantity: quantity,
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      reference: reference,
      notes: notes,
      userId: userId,
      locationFrom: locationFrom,
      locationTo: locationTo,
      orderId: orderId,
    );

    // Persist movement
    await _movementRepo.save(movement);

    // Update product stock
    await _productRepo.updateStock(productId, stockAfter);

    // Generate alerts if needed
    await _checkAndGenerateAlerts(
        product.copyWith(currentStock: stockAfter));

    return movement;
  }

  /// Convenience: receive goods (stock in).
  Future<StockMovement> receiveStock({
    required String productId,
    required double quantity,
    String? reference,
    String? notes,
    String? userId,
  }) =>
      recordMovement(
        productId: productId,
        type: MovementType.stockIn,
        quantity: quantity,
        reference: reference,
        notes: notes,
        userId: userId,
      );

  /// Convenience: dispatch goods (stock out).
  Future<StockMovement> dispatchStock({
    required String productId,
    required double quantity,
    String? reference,
    String? notes,
    String? userId,
  }) =>
      recordMovement(
        productId: productId,
        type: MovementType.stockOut,
        quantity: quantity,
        reference: reference,
        notes: notes,
        userId: userId,
      );

  /// Convenience: adjust stock to a target level.
  Future<StockMovement> adjustStock({
    required String productId,
    required double targetStock,
    String? notes,
    String? userId,
  }) async {
    final product = await _productRepo.getById(productId);
    if (product == null) throw StateError('Product $productId not found');

    final diff = targetStock - product.currentStock;
    if (diff == 0) throw StateError('No change in stock level');

    return recordMovement(
      productId: productId,
      type: MovementType.adjustment,
      quantity: diff.abs(),
      notes: notes ?? 'Manual adjustment to $targetStock',
      userId: userId,
    );
  }

  // ── Alert generation ──────────────────────────────────────────────────────

  Future<void> _checkAndGenerateAlerts(Product product) async {
    if (product.isOutOfStock) {
      await _createAlertIfNotExists(
        product: product,
        type: AlertType.outOfStock,
        severity: AlertSeverity.critical,
        message:
            '${product.name} is OUT OF STOCK. Current: ${product.currentStock} ${product.unit.name}',
      );
    } else if (product.isLowStock) {
      await _createAlertIfNotExists(
        product: product,
        type: AlertType.lowStock,
        severity: AlertSeverity.warning,
        message:
            '${product.name} is LOW on stock. Current: ${product.currentStock} | Min: ${product.minimumStock} ${product.unit.name}',
      );
    }

    if (product.needsReorder && !product.isLowStock) {
      await _createAlertIfNotExists(
        product: product,
        type: AlertType.reorderRequired,
        severity: AlertSeverity.info,
        message:
            '${product.name} has reached reorder point. Suggested reorder: ${product.reorderQty} ${product.unit.name}',
      );
    }
  }

  Future<void> _createAlertIfNotExists({
    required Product product,
    required AlertType type,
    required AlertSeverity severity,
    required String message,
  }) async {
    final exists = await _alertRepo.alertExistsForProduct(product.id, type);
    if (exists) return;

    final alert = StockAlert(
      id: _uuid.v4(),
      productId: product.id,
      productName: product.name,
      type: type,
      severity: severity,
      message: message,
      currentStock: product.currentStock,
      threshold: product.minimumStock,
    );
    await _alertRepo.save(alert);
  }

  // ── Stock check ───────────────────────────────────────────────────────────

  /// Re-evaluate all products and regenerate alerts.
  Future<int> runAlertScan() async {
    int generated = 0;
    final products = await _productRepo.getAllProducts();

    // Clean up dismissed/old alerts first
    await _alertRepo.deleteOldAlerts();

    for (final product in products) {
      if (product.status != ProductStatus.active) continue;
      final before = await _alertRepo.getActiveAlerts();
      await _checkAndGenerateAlerts(product);
      final after = await _alertRepo.getActiveAlerts();
      generated += (after.length - before.length);
    }
    return generated;
  }
}
