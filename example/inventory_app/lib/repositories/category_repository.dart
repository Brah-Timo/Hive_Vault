// example/inventory_app/lib/repositories/category_repository.dart

import '../models/category.dart';
import 'vault_repository.dart';

class CategoryRepository extends VaultRepository<ProductCategory> {
  CategoryRepository(super.vault);

  static const _prefix = 'category:';

  @override
  String keyFor(ProductCategory item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(ProductCategory item) => item.toMap();

  @override
  ProductCategory fromMap(Map<String, dynamic> map) =>
      ProductCategory.fromMap(map);

  @override
  String searchableText(ProductCategory item) =>
      '${item.name} ${item.description ?? ''}';

  Future<ProductCategory?> getById(String id) => get('$_prefix$id');

  Future<List<ProductCategory>> getAllCategories() async {
    final keys = (await vault.getAllKeys())
        .where((k) => k.startsWith(_prefix))
        .toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    return maps.values
        .whereType<Map<String, dynamic>>()
        .map(ProductCategory.fromMap)
        .toList();
  }

  Future<void> ensureDefaultsExist() async {
    for (final cat in kDefaultCategories) {
      if (!await contains(keyFor(cat))) {
        await save(cat);
      }
    }
  }
}
