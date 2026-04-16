# HiveVault

> **Advanced Secure Storage Wrapper for Flutter** — a production-grade middleware layer over [Hive](https://pub.dev/packages/hive) that adds AES-256-GCM/CBC encryption, GZip/LZ4 compression, O(1) in-memory indexing, ACID transactions, a fluent query DSL, plugin middleware, Prometheus-compatible metrics, horizontal sharding, sync/conflict resolution, and automated key rotation.


<img width="1408" height="768" alt="image" src="https://github.com/user-attachments/assets/65107a7d-962d-495b-bae4-24a7511baafb" />


[![Dart SDK](https://img.shields.io/badge/Dart-≥3.0.0-blue)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-≥3.10-blue)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/your-org/hive_vault/hive_vault_ci.yml?label=CI)](https://github.com/your-org/hive_vault/actions)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Core CRUD Operations](#core-crud-operations)
6. [Compression](#compression)
7. [Encryption](#encryption)
8. [Full-Text Search & Indexing](#full-text-search--indexing)
9. [LRU Memory Cache](#lru-memory-cache)
10. [Audit Logging](#audit-logging)
11. [TTL — Auto-Expiring Entries](#ttl--auto-expiring-entries)
12. [Reactive Streams](#reactive-streams)
13. [Multi-Box Vault](#multi-box-vault)
14. [Schema Migrations](#schema-migrations)
15. [Health Checks](#health-checks)
16. [**[NEW] Advanced Query DSL**](#new-advanced-query-dsl)
17. [**[NEW] Transaction Manager**](#new-transaction-manager)
18. [**[NEW] Plugin / Middleware System**](#new-plugin--middleware-system)
19. [**[NEW] Observability & Metrics**](#new-observability--metrics)
20. [**[NEW] Data Sharding**](#new-data-sharding)
21. [**[NEW] Rate Limiting**](#new-rate-limiting)
22. [**[NEW] Conflict Resolution**](#new-conflict-resolution)
23. [**[NEW] Vault Synchronizer**](#new-vault-synchronizer)
24. [**[NEW] Key Rotation Scheduler**](#new-key-rotation-scheduler)
25. [Import / Export](#import--export)
26. [VaultFactory](#vaultfactory)
27. [Configuration Reference](#configuration-reference)
28. [Exception Hierarchy](#exception-hierarchy)
29. [Testing](#testing)
30. [CI / CD](#ci--cd)
31. [Changelog — Batches 11-12](#changelog--batches-11-12)

---

## Overview

HiveVault wraps every Hive box in a full security, compression, and observability pipeline:

```
secureSave(key, value)
    │
    ▼
JSON / binary serialisation
    │
    ▼
Compression  (GZip | LZ4 | Deflate | Auto | None)
    │
    ▼
Encryption   (AES-256-GCM | AES-256-CBC | None)
    │
    ▼
Binary envelope  [magic | version | flags | length | data | checksum]
    │
    ▼
Hive Box  (persisted to disk)
```

Reading reverses the pipeline exactly.

---

## Architecture

```
hive_vault/
├─ lib/
│  ├─ hive_vault.dart          ← single public barrel export
│  └─ src/
│     ├─ core/                 ← config, interfaces, exceptions, stats
│     ├─ compression/          ← GZip, LZ4, Deflate, Auto, None providers
│     ├─ encryption/           ← AES-GCM, AES-CBC, key manager, key rotation
│     ├─ indexing/             ← tokenizer, inverted index engine
│     ├─ binary/               ← payload framing & integrity checks
│     ├─ cache/                ← LRU cache, rate limiter
│     ├─ audit/                ← ring-buffer audit logger
│     ├─ background/           ← Flutter compute() isolate offload
│     ├─ impl/                 ← HiveVaultImpl, factory, TTL, reactive, health
│     ├─ query/                ← [NEW] fluent Query DSL              (Batch 11)
│     ├─ transaction/          ← [NEW] ACID transaction manager      (Batch 11)
│     ├─ plugin/               ← [NEW] plugin / middleware system    (Batch 11)
│     ├─ observability/        ← [NEW] metrics & Prometheus export   (Batch 11)
│     ├─ sharding/             ← [NEW] horizontal shard manager      (Batch 11)
│     └─ sync/                 ← [NEW] sync + conflict resolution    (Batch 11)
├─ test/                       ← 250+ test cases across all modules
└─ example/                    ← 6 runnable example files
```

---

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  hive_vault:
    git:
      url: https://github.com/your-org/hive_vault.git
```

Run:

```bash
flutter pub get
```

---

## Quick Start

```dart
import 'package:hive_vault/hive_vault.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  await Hive.initFlutter();

  final vault = await VaultFactory.create(
    boxName: 'myApp',
    config: VaultConfig.secure(password: 'my-secret-password'),
  );

  await vault.secureSave('user:1', {'name': 'Alice', 'role': 'admin'});
  final user = await vault.secureGet<Map<String, dynamic>>('user:1');
  print(user); // {name: Alice, role: admin}

  await vault.close();
}
```

---

## Core CRUD Operations

```dart
// Save with explicit sensitivity level
await vault.secureSave(
  'session:token',
  tokenValue,
  sensitivity: SensitivityLevel.critical,
  searchableText: 'alice admin session',
);

// Get (returns null if missing)
final token = await vault.secureGet<String>('session:token');

// Check existence
final exists = await vault.secureContains('session:token');

// Delete
await vault.secureDelete('session:token');

// Batch operations
await vault.secureSaveBatch({'k1': v1, 'k2': v2, 'k3': v3});
final results = await vault.secureGetBatch(['k1', 'k2', 'k3']);
await vault.secureDeleteBatch(['k1', 'k2']);

// List all keys
final keys = await vault.getAllKeys();
```

---

## Compression

```dart
// GZip (best compatibility)
config: VaultConfig(compression: CompressionConfig.gzip())

// LZ4 (fastest, pure-Dart implementation)
config: VaultConfig(compression: CompressionConfig.lz4())

// Deflate
config: VaultConfig(compression: CompressionConfig.deflate())

// Auto — selects algorithm by payload size
config: VaultConfig(compression: CompressionConfig.auto())

// Disabled
config: VaultConfig(compression: CompressionConfig.none())
```

---

## Encryption

```dart
// AES-256-GCM (recommended — authenticated encryption)
config: VaultConfig(
  encryption: EncryptionConfig.aesGcm(password: 'my-password'),
)

// AES-256-CBC
config: VaultConfig(
  encryption: EncryptionConfig.aesCbc(password: 'my-password'),
)

// Per-entry sensitivity override
await vault.secureSave('pii:ssn', ssnValue,
  sensitivity: SensitivityLevel.critical);

// Sensitivity levels
// SensitivityLevel.public    → no encryption
// SensitivityLevel.internal  → encryption optional (config-driven)
// SensitivityLevel.sensitive → always encrypted
// SensitivityLevel.critical  → always encrypted + extra audit
```

---

## Full-Text Search & Indexing

```dart
// AND search — all tokens must match
final results = await vault.secureSearch<Employee>('alice engineering');

// OR search — any token matches
final any = await vault.secureSearchAny<Employee>('sales hr');

// Prefix search
final prefixed = await vault.secureSearchPrefix<Employee>('eng');

// Keys only (no deserialization)
final keys = await vault.searchKeys('alice');

// Rebuild index after bulk import
await vault.rebuildIndex();
```

---

## LRU Memory Cache

Configured in `VaultConfig`:

```dart
VaultConfig(
  enableMemoryCache: true,
  memoryCacheSize: 500,   // max 500 entries in RAM
)
```

The cache is automatically invalidated on delete and populated on first read.

---

## Audit Logging

```dart
// Retrieve recent entries
final log = vault.getAuditLog(limit: 100);
for (final entry in log) {
  print('${entry.timestamp} ${entry.action.name} ${entry.key}');
}
```

Every `secureSave`, `secureGet`, `secureDelete`, `export`, `import`, and `search` call is automatically recorded.

---

## TTL — Auto-Expiring Entries

```dart
final ttl = TtlManager(dataBoxName: 'sessions');
await ttl.initialize();

// Set 24-hour expiry
await ttl.setExpiry('session:abc', Duration(hours: 24));

// Check
if (ttl.isExpired('session:abc')) {
  await vault.secureDelete('session:abc');
}

// Auto-purge every 5 minutes
ttl.startAutoPurge(
  interval: Duration(minutes: 5),
  onExpired: (key) => vault.secureDelete(key),
);
```

---

## Reactive Streams

```dart
final reactive = ReactiveVault(myVault);

// Watch all changes
reactive.watchAll.listen((event) {
  print('${event.type.name} on ${event.key}');
});

// Watch single key
reactive.watch('user:1').listen((event) {
  // Rebuild widget
});

// Watch a set of keys
reactive.watchKeys({'user:1', 'user:2'}).listen((_) { ... });
```

---

## Multi-Box Vault

```dart
final multi = MultiBoxVault(
  vaults: {
    'users':    usersVault,
    'sessions': sessionsVault,
    'products': productsVault,
  },
);

await multi.secureSave('users/user:1', userData);
await multi.secureSave('sessions/sess:abc', sessionData);
```

---

## Schema Migrations

```dart
class AddTimestampMigration implements VaultMigration {
  @override int get fromVersion => 1;
  @override int get toVersion   => 2;
  @override String get description => 'Add createdAt timestamp to all entries';

  @override
  Future<Uint8List> migrate(Uint8List oldPayload) async {
    // Transform the binary payload: decode → add field → re-encode
    ...
    return newPayload;
  }
}

final manager = MigrationManager([AddTimestampMigration()]);
await manager.migrate(box, currentVersion: 1, targetVersion: 2);
```

---

## Health Checks

```dart
final report = await VaultHealthChecker.check(vault);
print(report);

if (report.hasCritical) {
  // Alert ops team
}
if (!report.isHealthy) {
  for (final issue in report.issues) {
    print('[${issue.severity.name}] ${issue.code}: ${issue.message}');
    if (issue.recommendation != null) print('  → ${issue.recommendation}');
  }
}
```

---

## [NEW] Advanced Query DSL

A fluent, composable, type-safe API for complex vault queries.

```dart
import 'package:hive_vault/hive_vault.dart';

// Filter + sort + paginate
final result = await VaultQuery<Map<String, dynamic>>()
    .where('department').equals('Engineering')
    .and('salary').greaterThan(80000)
    .or('role').contains('Senior')
    .orderByDesc('salary')
    .limit(10)
    .offset(0)
    .execute(vault);

print('Found ${result.totalCount} matches, page has ${result.records.length}');
print('Has more pages: ${result.hasMore}  Next offset: ${result.nextOffset}');
```

### Supported operators

| Operator              | Example                                          |
|-----------------------|--------------------------------------------------|
| `equals`              | `.where('status').equals('active')`              |
| `notEquals`           | `.and('role').notEquals('guest')`                |
| `greaterThan`         | `.and('age').greaterThan(18)`                    |
| `greaterThanOrEqual`  | `.and('score').greaterThanOrEqual(90)`           |
| `lessThan`            | `.and('price').lessThan(100)`                    |
| `lessThanOrEqual`     | `.and('stock').lessThanOrEqual(0)`               |
| `contains`            | `.where('name').contains('alice')`               |
| `startsWith`          | `.where('email').startsWith('admin')`            |
| `endsWith`            | `.where('file').endsWith('.pdf')`                |
| `isIn`                | `.where('tag').isIn(['new','sale'])`             |
| `isNotIn`             | `.and('status').isNotIn(['deleted','banned'])`   |
| `isNull`              | `.where('deletedAt').isNull()`                   |
| `isNotNull`           | `.where('email').isNotNull()`                    |
| `between`             | `.and('salary').between(50000, 100000)`          |
| `matchesRegex`        | `.where('code').matchesRegex(r'^[A-Z]{3}\d+$')` |

### Dot-notation for nested fields

```dart
VaultQuery<Map>()
    .where('address.city').equals('London')
    .and('contact.email').isNotNull()
    .execute(vault);
```

### Field projection

```dart
// Include only specific fields
VaultQuery<Map>().select(['id', 'name', 'email']).execute(vault);

// Exclude sensitive fields
VaultQuery<Map>().exclude(['password', 'ssn', 'card']).execute(vault);
```

### Key prefix scan

```dart
// Only scan keys starting with 'user:'
VaultQuery<Map>().keyPrefix('user:').execute(vault);
```

---

## [NEW] Transaction Manager

ACID-style transactions with read-your-writes consistency, savepoints, and automatic rollback.

```dart
final txManager = VaultTransactionManager(vault);

// Option A: auto commit/rollback helper
final receipt = await txManager.runInTransaction((tx) async {
  tx.write('order:1001', newOrder);
  tx.write('inventory:SKU-42', updatedStock);
  tx.delete('cart:user:7');
});

print('Committed: ${receipt.writes} writes, ${receipt.deletes} deletes, '
      '${receipt.elapsed.inMilliseconds}ms');

// Option B: manual control
final tx = txManager.begin();
try {
  tx.write('a', valueA);
  final sp = tx.savepoint('before-risky');  // create savepoint
  tx.write('b', valueBRisky);
  if (somethingWentWrong) {
    tx.rollbackToSavepoint(sp);             // revert to savepoint
  }
  // read-your-writes: see staged values before commit
  final staged = await tx.read<String>('a');
  await tx.commit();
} catch (e) {
  await tx.rollback();
  rethrow;
}
```

### Transaction properties

| Property              | Description                                        |
|-----------------------|----------------------------------------------------|
| **Atomicity**         | All writes commit together or none do              |
| **Read-your-writes**  | Staged values visible within the same transaction  |
| **Savepoints**        | Named checkpoints with partial rollback            |
| **Isolation**         | Optimistic — pending writes invisible to others    |
| **Durability**        | After `commit()` every write reaches Hive          |

---

## [NEW] Plugin / Middleware System

Intercept vault operations without modifying core code.

```dart
final vault = PluggableVault(inner: rawVault)
  ..use(SchemaValidationPlugin(requiredFields: {
    'name': String,
    'age': int,
  }))
  ..use(FieldMaskingPlugin(maskedFields: {'password', 'ssn', 'card'}))
  ..use(KeyNamingPlugin(pattern: RegExp(r'^[a-z]+:\d+$'), description: 'entity:id'))
  ..use(TimingPlugin())
  ..use(ConsoleLoggingPlugin(verbose: true));
```

### Built-in plugins

| Plugin                    | Priority | Description                                          |
|---------------------------|----------|------------------------------------------------------|
| `ConsoleLoggingPlugin`    | 10       | Logs all operations to stdout (debug)                |
| `FieldMaskingPlugin`      | 20       | Replaces sensitive fields with `***` before save     |
| `SchemaValidationPlugin`  | 5        | Validates required fields & types; cancels on fail   |
| `KeyNamingPlugin`         | 1        | Enforces key naming conventions via regex            |
| `TimingPlugin`            | 100      | Records per-operation latency in µs                  |

### Writing a custom plugin

```dart
class MyAuditWebhookPlugin extends VaultPlugin {
  @override String get name => 'audit_webhook';

  @override
  Future<void> afterSave(PluginContext ctx) async {
    await httpClient.post(webhookUrl, body: {
      'key': ctx.key,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> onError(PluginContext ctx, Object error) async {
    await alertingService.report(error, context: ctx.key);
  }
}
```

**Cancelling an operation from a plugin:**

```dart
@override
Future<void> beforeSave(PluginContext ctx) async {
  if (!isAllowed(ctx.key)) {
    ctx.cancelled = true;
    ctx.cancellationReason = 'Access denied by policy';
  }
}
```

---

## [NEW] Observability & Metrics

Structured telemetry with latency histograms, counters, throughput, and Prometheus export.

```dart
final metrics = VaultMetrics(vaultName: 'users');

// Record operations (called automatically by the metrics decorator)
metrics.recordOperation(
  MetricOperation.write,
  durationUs: stopwatch.elapsedMicroseconds,
  bytes: payload.length,
);

// Instant snapshot
final snap = metrics.snapshot();
print('Writes: ${snap.counters['write']}');
print('Error rate: ${(snap.errorRate * 100).toStringAsFixed(2)}%');
print('Cache hit ratio: ${(metrics.cacheHitRatio * 100).toStringAsFixed(1)}%');

// Latency percentiles
final writeHist = metrics.histogramFor(MetricOperation.write);
print('p50: ${writeHist.p50}µs  p95: ${writeHist.p95}µs  p99: ${writeHist.p99}µs');

// Periodic snapshots (for dashboards)
metrics.startPeriodicSnapshots(interval: Duration(seconds: 30));
metrics.snapshots.listen((snap) => myDashboard.push(snap));

// Prometheus export
final prometheusText = metrics.toPrometheusText();
// → hive_vault_users_operations_total{operation="write"} 1024
// → hive_vault_users_latency_microseconds{operation="write",quantile="0.99"} 8500

// Delta between two snapshots
final snap1 = metrics.snapshot();
await Future.delayed(Duration(minutes: 1));
final snap2 = metrics.snapshot();
final delta = snap2.delta(snap1); // shows only the diff
```

---

## [NEW] Data Sharding

Horizontally partition data across multiple Hive boxes.

```dart
final shards = [
  ShardDescriptor(index: 0, boxName: 'vault_users',    vault: usersVault),
  ShardDescriptor(index: 1, boxName: 'vault_orders',   vault: ordersVault),
  ShardDescriptor(index: 2, boxName: 'vault_products',  vault: productsVault),
  ShardDescriptor(index: 3, boxName: 'vault_misc',      vault: miscVault),
];

final manager = ShardManager(
  shards: shards,
  strategy: PrefixRoutingStrategy({
    'user:':    0,
    'order:':   1,
    'product:': 2,
  }, defaultShard: 3),
);

await manager.initialize();

// All CRUD / search / batch operations are transparently routed
await manager.secureSave('user:42', userData);
await manager.secureSave('order:1001', orderData);

// Check balance
final balance = await manager.balanceReport();
// → {vault_users: 1500, vault_orders: 8200, vault_products: 450, vault_misc: 72}
```

### Routing strategies

| Strategy              | Description                                              |
|-----------------------|----------------------------------------------------------|
| `ConsistentHashStrategy` | DJB2-based ring hash — even distribution             |
| `PrefixRoutingStrategy`  | Route by key prefix (ideal for entity-type prefixes) |
| `ModuloStrategy`         | Fast modulo on numeric key suffixes                  |
| `CustomRoutingStrategy`  | Caller-supplied `(key, count) → int` function        |

---

## [NEW] Rate Limiting

Prevent burst overloads with token-bucket, sliding-window, and per-key limiters.

```dart
// Token bucket — allows bursts up to capacity
final bucket = TokenBucket(capacity: 100, refillRate: 50); // 50 ops/sec
if (!bucket.tryConsume()) throw RateLimitExceededException('...');

// Async wait until tokens available
await bucket.consumeAsync();

// Sliding window — no burst
final window = SlidingWindowLimiter(maxRequests: 100, window: Duration(seconds: 1));
window.acquire(); // throws if exceeded

// Per-key limiting (e.g., per-user throttle)
final perKey = PerKeyRateLimiter(capacity: 10, refillRate: 5);
perKey.consume('user:42'); // throws if user:42 exceeded

// Vault-level composite limiter
final limiter = VaultRateLimiter.mobile(); // conservative profile
limiter.checkWrite();  // throws RateLimitExceededException if exceeded
limiter.checkRead();
limiter.checkSearch();

// Built-in profiles
VaultRateLimiter.standard(); // 1000w/sec, 5000r/sec, 100s/sec
VaultRateLimiter.mobile();   // 50w/sec,   200r/sec,  10s/sec
```

---

## [NEW] Conflict Resolution

Resolve data conflicts when syncing from multiple sources.

```dart
// Last-write-wins (default)
const resolver = LastWriteWinsResolver<Map<String, dynamic>>();

// Field-level merge
final mergeResolver = FieldMergeResolver(
  localPriorityFields: {'lastModifiedLocally', 'localNotes'},
  remotePriorityFields: {'serverVersion', 'syncedAt'},
);

// Vector-clock causal ordering (falls back to LWW for concurrent versions)
final vvResolver = VersionVectorResolver<Map>(
  fallback: FieldMergeResolver(),
);

// Resolve a detected conflict
final conflict = VaultConflict<Map>(
  key: 'user:42',
  local: VersionedValue(value: localData, sourceId: 'device-A',
      timestamp: localTs, version: 3, vectorClock: {'A': 3, 'B': 1}),
  remote: VersionedValue(value: remoteData, sourceId: 'server',
      timestamp: remoteTs, version: 5, vectorClock: {'A': 2, 'B': 5}),
);

final resolution = await mergeResolver.resolve(conflict);
print('Strategy: ${resolution.strategy.name}');
await vault.secureSave(conflict.key, resolution.resolvedValue);

// Deferred — queue for manual resolution
final deferred = DeferredResolver<Map>();
await deferred.resolve(conflict); // stores locally
final pending = deferred.pendingConflicts; // inspect and resolve manually
deferred.resolveManually('user:42', mergedValue);
```

---

## [NEW] Vault Synchronizer

Bidirectional sync between local vault and a remote data source.

```dart
// Implement the remote adapter
class MyRestRemote implements RemoteDataSource {
  @override
  Future<Map<String, String>> fetchSince(int cursor) async {
    final resp = await http.get('/api/vault/changes?since=$cursor');
    return Map<String, String>.from(jsonDecode(resp.body));
  }

  @override Future<void> push(Map<String, String> entries) async {
    await http.post('/api/vault/push', body: jsonEncode(entries));
  }

  @override Future<void> deleteKeys(List<String> keys) async {
    await http.post('/api/vault/delete', body: jsonEncode(keys));
  }

  @override Future<int> getRemoteCursor() async {
    return jsonDecode((await http.get('/api/vault/cursor')).body)['cursor'];
  }
}

// Wire up the synchronizer
final sync = VaultSynchronizer<Map<String, dynamic>>(
  local: myVault,
  remote: MyRestRemote(),
  resolver: LastWriteWinsResolver(),
  config: SyncConfig(
    enablePeriodicSync: true,
    syncInterval: Duration(minutes: 15),
    batchSize: 500,
  ),
);

await sync.initialize();
sync.startPeriodicSync();

// Manual trigger
final result = await sync.syncNow();
print('Pulled: ${result.pulled}, Pushed: ${result.pushed}, '
    'Conflicts: ${result.conflicts}, Resolved: ${result.resolved}');

// Monitor events
sync.events.listen((event) => print('[SYNC] ${event.type.name}: ${event.message}'));
```

---

## [NEW] Key Rotation Scheduler

Automated encryption key rotation with configurable policies.

```dart
final scheduler = KeyRotationScheduler(
  vault: myVault,
  policy: KeyRotationPolicy(
    rotationInterval: Duration(hours: 24),   // time-based
    maxEncryptOperations: 10000,             // count-based
    reEncryptExisting: true,                 // re-encrypt all entries on rotate
    archiveSize: 5,                          // keep last 5 rotations in history
  ),
  keyFactory: (generation) async {
    // Generate a new EncryptionProvider for this generation
    final newPassword = await keyDerivationService.deriveKey(generation);
    return AesGcmProvider.fromPassword(newPassword);
  },
);

await scheduler.initialize();
scheduler.start(); // starts the time-based timer

// Force rotation immediately
final event = await scheduler.rotateNow(reason: 'security-incident');
print('Rotated to gen ${event.generation}, re-encrypted ${event.entriesReEncrypted} entries');

// Listen for rotation events
scheduler.onRotation.listen((event) {
  print('Key rotated: gen=${event.generation}, reason=${event.reason}');
  analyticsService.track('key_rotation', event.toJson());
});

// Check rotation state
print('Current generation: ${scheduler.currentGeneration}');
print('Is rotation due: ${scheduler.isRotationDue}');
print('Last rotation: ${scheduler.lastRotation}');
```

#### Rotation policies

| Policy                        | Description                               |
|-------------------------------|-------------------------------------------|
| `KeyRotationPolicy.daily()`   | Rotate every 24 hours                     |
| `KeyRotationPolicy.countBased()` | Rotate every 10,000 encrypt operations  |
| `KeyRotationPolicy.manual()`  | Only rotate on explicit `rotateNow()` call|
| Custom                        | Combine any mix of the above              |

---

## Import / Export

```dart
// Export all entries as encrypted binary archive
final archive = await vault.exportEncrypted();
await File('backup.hvault').writeAsBytes(archive);

// Import into another vault (e.g., disaster recovery)
final data = await File('backup.hvault').readAsBytes();
await restoredVault.importEncrypted(data);
```

---

## VaultFactory

```dart
// Built-in configuration presets
final vault = await VaultFactory.create(
  boxName: 'app_data',
  config: VaultConfig.secure(password: 'password'),   // AES-GCM + GZip
);

// ERP preset (high-performance, auto compression, full audit)
final erp = await VaultFactory.create(
  boxName: 'erp',
  config: VaultConfig.erp(),
);

// Mobile preset (optimised for low battery + small RAM)
final mobile = await VaultFactory.create(
  boxName: 'app',
  config: VaultConfig.mobile(password: 'pass'),
);

// Register named vaults
VaultFactory.register('users', usersVault);
final same = VaultFactory.get('users');
```

---

## Configuration Reference

```dart
VaultConfig(
  // Compression
  compression: CompressionConfig.auto(),

  // Encryption
  encryption: EncryptionConfig.aesGcm(password: 'pass'),

  // Indexing
  indexing: IndexingConfig(
    enableAutoIndexing: true,
    indexableFields: {'name', 'email', 'description'},
    minimumTokenLength: 3,
    buildIndexInBackground: true,
  ),

  // Cache
  enableMemoryCache: true,
  memoryCacheSize: 500,

  // Integrity
  enableIntegrityChecks: true,

  // Background processing
  enableBackgroundProcessing: true,
  backgroundProcessingThreshold: 2048, // bytes

  // Audit
  enableAuditLog: true,
)
```

---

## Exception Hierarchy

```
VaultException (abstract)
├─ VaultEncryptionException
├─ VaultDecryptionException
├─ VaultIntegrityException
├─ VaultKeyException
├─ VaultCompressionException
├─ VaultDecompressionException
├─ VaultInitException
├─ VaultStorageException
├─ VaultPayloadException
├─ VaultConfigException
├─ VaultExportException
├─ VaultImportException
├─ VaultTransactionException    ← [NEW] Batch 11
├─ VaultPluginException         ← [NEW] Batch 11
└─ RateLimitExceededException   ← [NEW] Batch 11
```

---

## Testing

```bash
# Run all tests
flutter test

# Run specific module tests
flutter test test/query/
flutter test test/transaction/
flutter test test/plugin/
flutter test test/observability/
flutter test test/sharding/
flutter test test/sync/

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

**Test coverage by module (250+ test cases total):**

| Module             | Test file                              | Cases |
|--------------------|----------------------------------------|-------|
| Compression        | test/compression/                      | 30+   |
| Encryption         | test/encryption/                       | 25+   |
| Indexing           | test/indexing/                         | 20+   |
| Binary             | test/binary/                           | 15+   |
| Cache/LRU          | test/cache/                            | 15+   |
| Integration        | test/integration/                      | 20+   |
| Query DSL          | test/query/query_dsl_test.dart         | 25+   |
| Transactions       | test/transaction/vault_transaction_test.dart | 20+ |
| Plugins            | test/plugin/vault_plugin_test.dart     | 22+   |
| Metrics            | test/observability/vault_metrics_test.dart | 25+ |
| Sharding           | test/sharding/shard_manager_test.dart  | 20+   |
| Conflict Resolver  | test/sync/conflict_resolver_test.dart  | 25+   |

---

## CI / CD

GitHub Actions workflow (`.github/workflows/hive_vault_ci.yml`) runs on every push:

1. **Analyze** — `flutter analyze` with strict lints
2. **Test** — `flutter test --coverage`
3. **Coverage gate** — lcov coverage must be ≥ 80 %
4. **Build** — validates the package compiles for all platforms

---

## Changelog — Batches 11-12

### Batch 11 — Advanced Features

| Feature | File | Description |
|---|---|---|
| **Query DSL** | `lib/src/query/query_dsl.dart` | Fluent type-safe query builder: 15 operators, AND/OR logic, dot-notation, sorting, pagination, projection |
| **Transaction Manager** | `lib/src/transaction/vault_transaction.dart` | ACID transactions: read-your-writes, savepoints, commit/rollback, receipts |
| **Plugin System** | `lib/src/plugin/vault_plugin.dart` | Middleware hooks (beforeSave/afterSave/beforeGet/afterGet/beforeDelete/afterDelete/onError) + 5 built-in plugins |
| **Observability** | `lib/src/observability/vault_metrics.dart` | Latency histograms, counters, Prometheus export, snapshot streams, delta computation |
| **Sharding** | `lib/src/sharding/shard_manager.dart` | Horizontal partitioning: 4 routing strategies, batch routing, shard balance reporting |
| **Rate Limiter** | `lib/src/cache/rate_limiter.dart` | TokenBucket, SlidingWindow, FixedWindow, PerKey, VaultRateLimiter composite with profiles |
| **Conflict Resolver** | `lib/src/sync/conflict_resolver.dart` | LWW, FWW, Remote/Local Wins, FieldMerge, VectorClock, Deferred, Custom + ConflictDetector |
| **Vault Synchronizer** | `lib/src/sync/vault_synchronizer.dart` | Pull/diff/merge/push protocol, periodic sync, event stream, cursor persistence |
| **Key Rotation** | `lib/src/encryption/key_rotation_scheduler.dart` | Time/count/size-based rotation, history persistence, re-encryption, rotation event stream |

### Batch 12 — Tests, Examples & Updates

| Deliverable | File | Description |
|---|---|---|
| Query DSL tests | `test/query/query_dsl_test.dart` | 25+ cases covering all operators, pagination, sorting, projection |
| Transaction tests | `test/transaction/vault_transaction_test.dart` | 20+ cases: commit, rollback, savepoints, read-your-writes |
| Plugin tests | `test/plugin/vault_plugin_test.dart` | 22+ cases: hooks, cancellation, masking, validation, naming |
| Metrics tests | `test/observability/vault_metrics_test.dart` | 25+ cases: histogram, counters, error rate, Prometheus, delta |
| Shard tests | `test/sharding/shard_manager_test.dart` | 20+ cases: routing, batch grouping, balance, stats |
| Conflict tests | `test/sync/conflict_resolver_test.dart` | 25+ cases: all 7 strategies, detector, vector clock, merge |
| Showcase example | `example/batch_11_12_showcase.dart` | Full runnable demo of all 9 new features |
| Updated barrel | `lib/hive_vault.dart` | Exports all 9 new modules |
| Updated README | `README.md` | Comprehensive docs for all 30 sections |

---

## Example: Inventory Management System

> **Location:** `example/inventory_app/`

A **complete, production-ready Flutter Inventory Management System** demonstrating
every HiveVault feature in a real-world context.

### Feature Matrix

| Feature | Description |
|---|---|
| Onboarding | 5-step walkthrough with demo-data loader & first-run detection |
| Barcode Scanner | `mobile_scanner` with Stock-In / Stock-Out / Info modes + manual entry |
| Product Management | Full CRUD, category & supplier assignment, custom fields |
| Stock Movements | 8 movement types (stockIn, stockOut, adjustment, transfer, return, damaged, expired) |
| Inventory Counting | Physical stocktake with barcode scan, variance reconciliation, bulk apply |
| Low-Stock Alerts | 3 severity levels (Critical / Warning / Info), dismissible, push notifications |
| Purchase Orders | Full 7-stage workflow (Draft → Sent → Confirmed → Partial → Received → Cancelled) |
| Auto Reorder | One-tap reorder request generation grouped by supplier |
| Reports | Low Stock, Valuation (pie chart), Movements (bar chart), Reorder, Summary |
| PDF Export | `pdf` + `printing` — printable reports and purchase orders |
| Global Search | Cross-entity search: products, suppliers, categories |
| Settings | Notification preferences, display options, vault stats, data clear |
| 7 Isolated Vaults | Products (AES-256-GCM + GZip + indexing), Movements (GZip), Settings (maxSecurity), … |
| Offline-first | All data stored locally in encrypted Hive boxes via HiveVault |
| Dark Mode | Full Material 3 light + dark theming |

### Architecture

```
example/inventory_app/lib/
├── main.dart                         # App entry, splash, first-run detection
├── models/                           # 7 data models (Product, Category, …)
├── repositories/                     # 7 VaultRepository subclasses
├── services/                         # VaultService, StockService, ReportService,
│                                     #   NotificationService, PdfService
├── providers/
│   └── inventory_provider.dart       # Central ChangeNotifier (850+ lines)
├── screens/
│   ├── onboarding/onboarding_screen.dart
│   ├── dashboard/dashboard_screen.dart
│   ├── products/                     # list, detail, form
│   ├── scanner/scanner_screen.dart
│   ├── stock/                        # movements list, movement form
│   ├── inventory/inventory_count_screen.dart
│   ├── alerts/alerts_screen.dart
│   ├── orders/                       # list, detail, form
│   ├── suppliers/suppliers_screen.dart
│   ├── categories/categories_screen.dart
│   ├── reports/reports_screen.dart   # 5 report sub-pages with charts
│   ├── search/global_search_screen.dart
│   └── settings/settings_screen.dart
├── widgets/                          # StatCard, ProductCard, StockStatusBadge, …
├── theme/app_theme.dart              # Material 3 light + dark
└── utils/                            # AppRoutes, formatters
```

### HiveVault Integration

```dart
// Seven isolated encrypted vaults
final productsVault = VaultFactory.create(
  boxName: 'inv_products',
  config: VaultConfig.erp(),           // AES-256-GCM + GZip6 + full-text index
);

final movementsVault = VaultFactory.create(
  boxName: 'inv_movements',
  config: VaultConfig(                  // High-volume: aggressive compression
    compression: CompressionConfig(
      strategy: CompressionStrategy.gzip,
      gzipLevel: 6,
    ),
    indexing: IndexingConfig(enableAutoIndexing: false),
    memoryCacheSize: 100,
  ),
);

final settingsVault = VaultFactory.create(
  boxName: 'inv_settings',
  config: VaultConfig.maxSecurity(),   // 200k PBKDF2 iterations
);
```

### Running the App

```bash
cd example/inventory_app
flutter pub get
flutter run
```

- **Android:** Requires `CAMERA` permission in `AndroidManifest.xml`
- **iOS:** Add `NSCameraUsageDescription` to `Info.plist`
- **First launch:** Shows onboarding; tap **Load Demo Data & Start** for sample products

### File Count & Metrics

| Metric | Value |
|---|---|
| Dart files | 48 |
| Lines of code | ~11,600 |
| Screens | 17 |
| Models | 7 |
| Repositories | 7 |
| Services | 5 |
| HiveVault instances | 7 |

---

## License

```
MIT License — Copyright (c) 2024 HiveVault Contributors
```

See [LICENSE](LICENSE) for full text.
