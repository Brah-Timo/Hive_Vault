// example/inventory_app/lib/repositories/purchase_order_repository.dart

import '../models/purchase_order.dart';
import 'vault_repository.dart';

class PurchaseOrderRepository extends VaultRepository<PurchaseOrder> {
  PurchaseOrderRepository(super.vault);

  static const _prefix = 'po:';

  @override
  String keyFor(PurchaseOrder item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(PurchaseOrder item) => item.toMap();

  @override
  PurchaseOrder fromMap(Map<String, dynamic> map) => PurchaseOrder.fromMap(map);

  @override
  String searchableText(PurchaseOrder item) =>
      '${item.orderNumber} ${item.supplierName} ${item.notes ?? ''}';

  Future<PurchaseOrder?> getById(String id) => get('$_prefix$id');

  Future<List<PurchaseOrder>> getAllOrders() async {
    final keys =
        (await vault.getAllKeys()).where((k) => k.startsWith(_prefix)).toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    final orders = maps.values
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrder.fromMap)
        .toList();
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  Future<List<PurchaseOrder>> getOrdersByStatus(
      PurchaseOrderStatus status) async {
    final all = await getAllOrders();
    return all.where((o) => o.status == status).toList();
  }

  Future<List<PurchaseOrder>> getPendingOrders() async {
    final all = await getAllOrders();
    return all
        .where((o) =>
            o.status != PurchaseOrderStatus.fullyReceived &&
            o.status != PurchaseOrderStatus.cancelled)
        .toList();
  }

  Future<List<PurchaseOrder>> getOrdersForSupplier(String supplierId) async {
    final all = await getAllOrders();
    return all.where((o) => o.supplierId == supplierId).toList();
  }

  Future<String> generateOrderNumber() async {
    final all = await getAllOrders();
    final num = (all.length + 1).toString().padLeft(5, '0');
    return 'PO-${DateTime.now().year}-$num';
  }
}
