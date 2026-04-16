// example/inventory_app/lib/repositories/supplier_repository.dart

import '../models/supplier.dart';
import 'vault_repository.dart';

class SupplierRepository extends VaultRepository<Supplier> {
  SupplierRepository(super.vault);

  static const _prefix = 'supplier:';

  @override
  String keyFor(Supplier item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(Supplier item) => item.toMap();

  @override
  Supplier fromMap(Map<String, dynamic> map) => Supplier.fromMap(map);

  @override
  String searchableText(Supplier item) =>
      '${item.name} ${item.contactName ?? ''} ${item.email ?? ''}';

  Future<Supplier?> getById(String id) => get('$_prefix$id');

  Future<List<Supplier>> getAllSuppliers() async {
    final keys = (await vault.getAllKeys())
        .where((k) => k.startsWith(_prefix))
        .toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    return maps.values
        .whereType<Map<String, dynamic>>()
        .map(Supplier.fromMap)
        .toList();
  }

  Future<List<Supplier>> getActiveSuppliers() async {
    final all = await getAllSuppliers();
    return all.where((s) => s.isActive).toList();
  }
}
