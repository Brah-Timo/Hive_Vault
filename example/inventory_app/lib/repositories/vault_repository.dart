// example/inventory_app/lib/repositories/vault_repository.dart
// ─────────────────────────────────────────────────────────────────────────────
// Base vault repository — wraps HiveVault with typed CRUD helpers.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:hive_vault/hive_vault.dart';

/// Generic base repository using HiveVault for typed, encrypted storage.
abstract class VaultRepository<T> {
  final SecureStorageInterface vault;

  VaultRepository(this.vault);

  // ── Subclass contract ─────────────────────────────────────────────────────

  String keyFor(T item);
  Map<String, dynamic> toMap(T item);
  T fromMap(Map<String, dynamic> map);

  /// Optional: text that will be indexed for full-text search.
  String searchableText(T item) => '';

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> save(T item) async {
    await vault.secureSave<Map<String, dynamic>>(
      keyFor(item),
      toMap(item),
      searchableText: searchableText(item),
    );
  }

  Future<T?> get(String key) async {
    final map = await vault.secureGet<Map<String, dynamic>>(key);
    return map != null ? fromMap(map) : null;
  }

  Future<void> delete(String key) => vault.secureDelete(key);

  Future<bool> contains(String key) => vault.secureContains(key);

  Future<void> saveAll(Iterable<T> items) async {
    final batch = <String, dynamic>{
      for (final item in items) keyFor(item): toMap(item),
    };
    await vault.secureSaveBatch(batch);
  }

  // ── Query ────────────────────────────────────────────────────────────────

  Future<List<T>> getAll() async {
    final keys = await vault.getAllKeys();
    final maps = await vault.secureGetBatch(keys);
    return maps.values.whereType<Map<String, dynamic>>().map(fromMap).toList();
  }

  Future<List<T>> search(String query) async {
    final maps = await vault.secureSearch<Map<String, dynamic>>(query);
    return maps.map(fromMap).toList();
  }

  Future<List<T>> searchAny(String query) async {
    final maps = await vault.secureSearchAny<Map<String, dynamic>>(query);
    return maps.map(fromMap).toList();
  }

  Future<List<T>> searchPrefix(String prefix) async {
    final maps = await vault.secureSearchPrefix<Map<String, dynamic>>(prefix);
    return maps.map(fromMap).toList();
  }

  // ── Bulk delete ───────────────────────────────────────────────────────────

  Future<void> deleteAll() async {
    final keys = await vault.getAllKeys();
    await vault.secureDeleteBatch(keys);
  }

  // ── Raw key/value access (for settings-like data) ─────────────────────────

  Future<void> saveRaw(String key, String value) async {
    await vault.secureSave<String>(key, value);
  }

  Future<String?> getRaw(String key) async {
    return vault.secureGet<String>(key);
  }

  // ── Stats ────────────────────────────────────────────────────────────────

  Future<VaultStats> stats() => vault.getStats();

  Future<void> rebuildIndex() => vault.rebuildIndex();

  Future<void> compact() => vault.compact();
}
