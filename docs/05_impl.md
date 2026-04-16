# Implementation Layer

> **Files**: `lib/src/impl/`
>
> - `hive_vault_impl.dart` — Core implementation of `SecureStorageInterface`
> - `vault_factory.dart` — Static factory: `HiveVault.open()` / `HiveVault.create()`
> - `vault_stats_counter.dart` — Mutable runtime counters
> - `migration_manager.dart` — Versioned payload migration engine
> - `multi_box_vault.dart` — Multi-module vault collection
> - `reactive_vault.dart` — Stream-emitting decorator (see doc 16)
> - `ttl_manager.dart` — Time-to-live management (see doc 20)
> - `vault_health.dart` — Health diagnostics (see doc 17)

---

## 1. `hive_vault_impl.dart` — `HiveVaultImpl`

The concrete implementation of `SecureStorageInterface`. Wires together all subsystems.

### Subsystem Wiring

```dart
class HiveVaultImpl implements SecureStorageInterface {
  final String boxName;
  final VaultConfig config;
  final CompressionProvider _compression;
  final EncryptionProvider _encryption;
  final InMemoryIndexEngine _index;
  final BinaryProcessor _binary;
  final LruCache<String, dynamic>? _cache;  // null if disabled
  final AuditLogger _audit;
  final BackgroundProcessor _background;
  final VaultStatsCounter _stats;

  late Box<Uint8List> _box;
  bool _initialised = false;
}
```

### Initialization

```dart
Future<void> initialize() async {
  _box = await Hive.openBox<Uint8List>(boxName);
  // Record open time in stats
  // Trigger auto-index:
  //   - If box has few entries (< threshold): rebuild synchronously
  //   - If large: rebuild in background isolate
}
```

### `secureSave<T>` — Write Pipeline

```
1. Serialize value to Uint8List (objectToBytes)
2. Choose compression:
   a. Skip if data.length < minimumSizeForCompression
   b. Compress via provider (background isolate if > threshold)
3. Encrypt via provider (background isolate if large)
4. Create binary envelope (createPayload):
   [version][compressionFlag][encryptionFlag][dataLen][data][SHA-256]
5. box.put(key, envelope)
6. indexEntry(key, searchableText) if indexing enabled
7. Record audit entry (action: save, sizes, elapsed)
8. Update stats (totalWrites, totalBytesWritten, totalBytesSaved)
9. Update cache if enabled
```

### `secureGet<T>` — Read Pipeline

```
1. Check LRU cache → return if hit (record audit: cacheHit)
2. box.get(key) → null → return null (record audit: cacheMiss)
3. parsePayload: verify header, verify SHA-256 checksum
4. Decrypt payload bytes
5. Decompress based on compressionFlag
6. Deserialize bytes to T (bytesToObject<T>)
7. Store in LRU cache
8. Record audit entry (action: get, elapsed, cache: false)
9. Update stats (totalReads)
```

### `secureSaveBatch` / `secureGetBatch`

Batch operations use `Future.wait` for parallel processing:

```dart
// secureSaveBatch: processes all entries in parallel
await Future.wait(entries.entries.map((e) => secureSave(e.key, e.value)));

// secureGetBatch: parallel reads, missing keys omitted
final results = await Future.wait(keys.map((k) => secureGet<dynamic>(k)));
```

### Search Flow

```dart
// secureSearch<T>(query):
1. engine.searchAll(query) → Set<String> matchingKeys
2. Fetch and decrypt each matching key (batch)
3. Return List<T>

// secureSearchAny<T>(query):
1. engine.searchAny(query) → Set<String> matchingKeys
2. Same fetch pipeline

// secureSearchPrefix<T>(prefix):
1. engine.searchPrefix(prefix) → Set<String>
2. Same fetch pipeline
```

### Export / Import

```dart
// exportEncrypted():
1. getAllKeys() → all box keys
2. For each key: box.get(key) → raw encrypted payload bytes
3. base64-encode each payload
4. JSON-encode the map: { "KEY": "base64...", ... }
5. Return UTF-8 bytes of the JSON string

// importEncrypted(data):
1. UTF-8 decode + JSON parse → Map<String, String>
2. For each entry: base64-decode → raw payload bytes
3. box.put(key, rawBytes) — stored as-is (already encrypted)
4. rebuildIndex() after import
```

### `getStats()` — Building the Stats Snapshot

```dart
Future<VaultStats> getStats() async {
  return VaultStats(
    boxName: boxName,
    totalEntries: _box.length,
    cacheSize: _cache?.length ?? 0,
    cacheCapacity: config.memoryCacheSize,
    cacheHitRatio: _cache != null
        ? (_stats.cacheHits / max(1, _stats.cacheHits + _stats.cacheMisses))
        : 0.0,
    compressionAlgorithm: _compression.algorithmName,
    encryptionAlgorithm: _encryption.algorithmName,
    indexStats: _index.getStats(),
    totalBytesSaved: _stats.totalBytesSaved,
    totalBytesWritten: _stats.totalBytesWritten,
    totalWrites: _stats.totalWrites,
    totalReads: _stats.totalReads,
    totalSearches: _stats.totalSearches,
    openedAt: _stats.openedAt,
  );
}
```

---

## 2. `vault_factory.dart` — `HiveVault`

Static factory that manages vault creation and a global instance registry.

### `initHive`

```dart
static Future<void> initHive({String? path}) async {
  // Sets Hive storage path (useful for tests / custom directories)
  if (path != null) Hive.init(path);
  // For Flutter: use path_provider to get the app documents directory
}
```

### `open`

```dart
static Future<SecureStorageInterface> open({
  required String boxName,
  required VaultConfig config,
  Uint8List? masterKey,         // Provide or let KeyManager generate/retrieve
}) async {
  // 1. Resolve master key (getOrCreateMasterKey if not provided)
  // 2. Build CompressionProvider via CompressionFactory.create(config.compression)
  // 3. Build EncryptionProvider via EncryptionFactory.create(config.encryption, key)
  // 4. Construct HiveVaultImpl
  // 5. Call vault.initialize()
  // 6. Register in _registry
  // 7. Return vault
}
```

### `create`

```dart
static Future<SecureStorageInterface> create({
  required String boxName,
  required VaultConfig config,
  Uint8List? masterKey,
}) async {
  // Same as open() but does NOT call initialize() — caller must do so
}
```

### Registry (multiple named vaults)

```dart
// Open or retrieve a named vault (singleton per boxName)
final vault = await HiveVault.getOrOpen(
  boxName: 'invoices',
  config: VaultConfig.erp(),
);

// Close a specific vault and remove from registry
await HiveVault.closeVault('invoices');

// Close ALL open vaults
await HiveVault.closeAll();
```

### Key Rotation Workflow

```dart
static Future<void> rotateKey({
  required String boxName,
  required String keyId,
}) async {
  // 1. Export all data with old key
  // 2. KeyManager.rotateKey(keyId) → new key
  // 3. Re-open vault with new key
  // 4. Import data (re-encrypts with new key)
  // 5. KeyManager.commitRotation()
  // 6. On any error: KeyManager.abortRotation()
}
```

---

## 3. `vault_stats_counter.dart` — `VaultStatsCounter`

Mutable accumulator for runtime metrics. Internal to `HiveVaultImpl`.

```dart
class VaultStatsCounter {
  DateTime openedAt = DateTime.now();

  int totalWrites = 0;
  int totalReads = 0;
  int totalSearches = 0;

  int totalOriginalBytesWritten = 0;  // Before compression
  int totalBytesWritten = 0;          // After compression + encryption
  int totalBytesSaved = 0;            // originalSize - finalSize (when positive)

  void recordWrite({required int originalSize, required int finalSize}) {
    totalWrites++;
    totalOriginalBytesWritten += originalSize;
    totalBytesWritten += finalSize;
    final saved = originalSize - finalSize;
    if (saved > 0) totalBytesSaved += saved;
  }

  void recordRead() => totalReads++;
  void recordSearch() => totalSearches++;

  void reset() {
    // Resets all counters and sets openedAt to now
  }
}
```

---

## 4. `migration_manager.dart` — `MigrationManager`

Handles upgrades when the binary payload format changes between library versions.

### `VaultMigration` (abstract)

```dart
abstract class VaultMigration {
  int get fromVersion;                         // Payload version this reads
  int get toVersion;                           // Payload version this produces
  Future<Uint8List> migrate(Uint8List oldPayload);
  String get description;                      // Human-readable description
}
```

### `MigrationManager`

```dart
class MigrationManager {
  const MigrationManager(List<VaultMigration> migrations);

  // Read the current schema version from the '__hive_vault_schema__' box
  static Future<int> getCurrentVersion() async;

  // Persist the new version
  static Future<void> setCurrentVersion(int version) async;

  // Run all pending migrations on a Hive box
  Future<void> migrate(
    Box<Uint8List> box,
    int currentVersion,
    int targetVersion,
  ) async;
}
```

### Usage

```dart
class MyMigrationV1toV2 extends VaultMigration {
  @override int get fromVersion => 1;
  @override int get toVersion   => 2;
  @override String get description => 'Add checksum to payload';

  @override
  Future<Uint8List> migrate(Uint8List oldPayload) async {
    // Reformat the old payload into the new format
    return newPayload;
  }
}

final manager = MigrationManager([
  MyMigrationV1toV2(),
]);

final currentVersion = await MigrationManager.getCurrentVersion();
await manager.migrate(box, currentVersion, targetVersion: 2);
```

### Migration Storage

Versions are persisted in a dedicated Hive box named `'__hive_vault_schema__'` under the key `'schema_version'`.

---

## 5. `multi_box_vault.dart` — `MultiBoxVault`

Groups multiple named vaults for ERP domain isolation.

```dart
class MultiBoxVault {
  final VaultConfig defaultConfig;
  final List<String> modules;
  final Map<String, VaultConfig> moduleConfigs;

  final Map<String, SecureStorageInterface> _vaults = {};
}
```

### Usage

```dart
final erp = MultiBoxVault(
  defaultConfig: VaultConfig.erp(),
  modules: ['clients', 'invoices', 'products', 'payslips', 'settings'],
  moduleConfigs: {
    'settings': VaultConfig.light(),  // Settings vault uses lighter config
  },
);

await erp.initialize();   // Opens all registered modules

// Access specific vault
final clientVault = erp['clients'];
final invoiceVault = erp.module('invoices');

// Check if a module is open
bool open = erp.isOpen('products');

// Cross-module search
Map<String, List<dynamic>> results = await erp.searchAll('acme');
// Returns: {'clients': [...], 'invoices': [...]}

// Reopen a specific vault (e.g., after key rotation)
await erp.reopen('payslips');

// Close all
await erp.close();
```

### `module()` vs `[]` Operator

Both `erp.module('clients')` and `erp['clients']` return the same `SecureStorageInterface`. `module()` throws a `VaultInitException` if the name was not registered; the `[]` operator delegates to `module()`.

### Per-Module Config

```dart
MultiBoxVault(
  defaultConfig: VaultConfig.erp(),
  modules: ['data', 'logs', 'cache'],
  moduleConfigs: {
    'logs': VaultConfig.light(),          // Faster, less secure for logs
    'cache': VaultConfig.maxPerformance(), // No encryption for temp cache
  },
)
```
