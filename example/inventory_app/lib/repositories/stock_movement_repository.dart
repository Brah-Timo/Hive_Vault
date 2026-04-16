// example/inventory_app/lib/repositories/stock_movement_repository.dart

import '../models/stock_movement.dart';
import 'vault_repository.dart';

class StockMovementRepository extends VaultRepository<StockMovement> {
  StockMovementRepository(super.vault);

  static const _prefix = 'movement:';

  @override
  String keyFor(StockMovement item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(StockMovement item) => item.toMap();

  @override
  StockMovement fromMap(Map<String, dynamic> map) => StockMovement.fromMap(map);

  @override
  String searchableText(StockMovement item) =>
      '${item.type.label} ${item.reference ?? ''} ${item.notes ?? ''}';

  Future<List<StockMovement>> getAllMovements() async {
    final keys = (await vault.getAllKeys())
        .where((k) => k.startsWith(_prefix))
        .toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    final items = maps.values
        .whereType<Map<String, dynamic>>()
        .map(StockMovement.fromMap)
        .toList();
    // Sort newest first
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<List<StockMovement>> getMovementsForProduct(String productId) async {
    final all = await getAllMovements();
    return all.where((m) => m.productId == productId).toList();
  }

  Future<List<StockMovement>> getMovementsByType(MovementType type) async {
    final all = await getAllMovements();
    return all.where((m) => m.type == type).toList();
  }

  Future<List<StockMovement>> getMovementsInRange(
      DateTime from, DateTime to) async {
    final all = await getAllMovements();
    return all
        .where((m) =>
            m.createdAt.isAfter(from) && m.createdAt.isBefore(to))
        .toList();
  }

  Future<List<StockMovement>> getRecentMovements({int limit = 50}) async {
    final all = await getAllMovements();
    return all.take(limit).toList();
  }
}
