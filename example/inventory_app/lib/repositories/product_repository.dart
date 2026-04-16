// example/inventory_app/lib/repositories/product_repository.dart

import '../models/product.dart';
import 'vault_repository.dart';

class ProductRepository extends VaultRepository<Product> {
  ProductRepository(super.vault);

  static const _prefix = 'product:';

  @override
  String keyFor(Product item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(Product item) => item.toMap();

  @override
  Product fromMap(Map<String, dynamic> map) => Product.fromMap(map);

  @override
  String searchableText(Product item) =>
      '${item.name} ${item.sku} ${item.barcode} '
      '${item.description ?? ''} ${item.location ?? ''}';

  // ── Domain-specific queries ───────────────────────────────────────────────

  Future<Product?> getById(String id) => get('$_prefix$id');

  Future<void> saveProduct(Product p) => save(p);

  Future<void> deleteProduct(String id) => delete('$_prefix$id');

  Future<List<Product>> getAll() async {
    final all = await super.getAll();
    // Filter to only product keys
    return all;
  }

  Future<List<Product>> getAllProducts() async {
    final keys =
        (await vault.getAllKeys()).where((k) => k.startsWith(_prefix)).toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    return maps.values
        .whereType<Map<String, dynamic>>()
        .map(Product.fromMap)
        .toList();
  }

  Future<List<Product>> getLowStockProducts() async {
    final all = await getAllProducts();
    return all
        .where((p) => p.isLowStock && p.status == ProductStatus.active)
        .toList();
  }

  Future<List<Product>> getOutOfStockProducts() async {
    final all = await getAllProducts();
    return all
        .where((p) => p.isOutOfStock && p.status == ProductStatus.active)
        .toList();
  }

  Future<List<Product>> getProductsByCategory(String categoryId) async {
    final all = await getAllProducts();
    return all.where((p) => p.categoryId == categoryId).toList();
  }

  Future<List<Product>> getProductsBySupplier(String supplierId) async {
    final all = await getAllProducts();
    return all.where((p) => p.supplierId == supplierId).toList();
  }

  Future<Product?> getByBarcode(String barcode) async {
    final all = await getAllProducts();
    try {
      return all.firstWhere((p) => p.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  Future<Product?> getBySku(String sku) async {
    final all = await getAllProducts();
    try {
      return all.firstWhere((p) => p.sku == sku);
    } catch (_) {
      return null;
    }
  }

  Future<List<Product>> searchProducts(String query) async {
    if (query.isEmpty) return getAllProducts();
    final q = query.toLowerCase();
    final all = await getAllProducts();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            p.barcode.toLowerCase().contains(q) ||
            (p.description?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<void> updateStock(String productId, double newStock) async {
    final product = await getById(productId);
    if (product == null) return;
    await saveProduct(product.copyWith(currentStock: newStock));
  }
}
