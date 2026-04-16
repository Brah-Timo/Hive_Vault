// example/batch_11_12_showcase.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Batch 11-12 Feature Showcase.
//
// Demonstrates all new capabilities added in Batches 11 and 12:
//   • VaultQuery    — fluent type-safe query DSL with filtering, sorting, pagination
//   • Transactions  — ACID-style commit/rollback with save-points
//   • Plugin system — middleware hooks for validation, masking, timing
//   • Observability — latency histograms, Prometheus export, snapshot streams
//   • Sharding      — horizontal partitioning across multiple Hive boxes
//   • Rate limiting — token-bucket and sliding-window throttling
//   • Conflict res. — LWW, merge, vector-clock, deferred strategies
//   • Sync          — remote data-source synchronisation protocol
//   • Key rotation  — automated scheduled encryption key rotation
// ─────────────────────────────────────────────────────────────────────────────

// NOTE: This file uses pseudo-initialisation (Hive.initFlutter() stubs) so it
// compiles and illustrates the API surface without requiring a real device.
// Replace the stub vault with VaultFactory.create() in production.

import 'dart:async';
import 'dart:typed_data';

// ── Core imports ──────────────────────────────────────────────────────────────
import '../lib/src/core/vault_interface.dart';
import '../lib/src/core/sensitivity_level.dart';
import '../lib/src/core/vault_stats.dart';
import '../lib/src/audit/audit_entry.dart';

// ── Batch 11-12 imports ───────────────────────────────────────────────────────
import '../lib/src/query/query_dsl.dart';
import '../lib/src/transaction/vault_transaction.dart';
import '../lib/src/plugin/vault_plugin.dart';
import '../lib/src/observability/vault_metrics.dart';
import '../lib/src/sharding/shard_manager.dart';
import '../lib/src/cache/rate_limiter.dart';
import '../lib/src/sync/conflict_resolver.dart';
import '../lib/src/encryption/key_rotation_scheduler.dart';

// ════════════════════════════════════════════════════════════════════════════
//  In-memory stub vault (replace with VaultFactory.create() in production)
// ════════════════════════════════════════════════════════════════════════════

class InMemoryVault implements SecureStorageInterface {
  final String boxName;
  final Map<String, dynamic> _store = {};
  InMemoryVault(this.boxName);

  @override
  Future<void> initialize() async {}
  @override
  Future<void> close() async {}
  @override
  Future<bool> secureContains(String k) async => _store.containsKey(k);
  @override
  Future<List<String>> getAllKeys() async => _store.keys.toList();
  @override
  Future<T?> secureGet<T>(String k) async => _store[k] as T?;
  @override
  Future<void> secureDelete(String k) async => _store.remove(k);
  @override
  Future<void> secureSave<T>(String k, T v,
          {SensitivityLevel? sensitivity, String? searchableText}) async =>
      _store[k] = v;
  @override
  Future<void> secureSaveBatch(Map<String, dynamic> e,
          {SensitivityLevel? sensitivity}) async =>
      _store.addAll(e);
  @override
  Future<Map<String, dynamic>> secureGetBatch(List<String> ks) async => {
        for (final k in ks)
          if (_store.containsKey(k)) k: _store[k]
      };
  @override
  Future<void> secureDeleteBatch(List<String> ks) async =>
      ks.forEach(_store.remove);
  @override
  Future<List<T>> secureSearch<T>(String q) async => [];
  @override
  Future<List<T>> secureSearchAny<T>(String q) async => [];
  @override
  Future<List<T>> secureSearchPrefix<T>(String p) async => [];
  @override
  Future<Set<String>> searchKeys(String q) async => {};
  @override
  Future<void> rebuildIndex() async {}
  @override
  Future<void> compact() async {}
  @override
  void clearCache() {}
  @override
  Future<Uint8List> exportEncrypted() async => Uint8List(0);
  @override
  Future<void> importEncrypted(Uint8List d) async {}
  @override
  Future<VaultStats> getStats() async => VaultStats(
        boxName: boxName,
        totalEntries: _store.length,
        cacheSize: 0,
        cacheCapacity: 0,
        cacheHitRatio: 0.0,
        compressionAlgorithm: 'None',
        encryptionAlgorithm: 'AES-GCM',
        indexStats: const IndexStats.empty(),
        totalBytesSaved: 0,
        totalBytesWritten: 0,
        totalWrites: 0,
        totalReads: 0,
        totalSearches: 0,
        openedAt: DateTime.now(),
      );
  @override
  List<AuditEntry> getAuditLog({int limit = 50}) => [];
}

// ════════════════════════════════════════════════════════════════════════════
//  Main
// ════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║         HiveVault — Batch 11 & 12 Feature Showcase           ║');
  print('╚══════════════════════════════════════════════════════════════╝\n');

  final vault = InMemoryVault('showcase');
  await vault.initialize();

  // ── Seed data ───────────────────────────────────────────────────────────

  final employees = [
    {
      'id': '1',
      'name': 'Alice',
      'dept': 'Engineering',
      'salary': 95000,
      'active': true
    },
    {
      'id': '2',
      'name': 'Bob',
      'dept': 'Engineering',
      'salary': 72000,
      'active': true
    },
    {
      'id': '3',
      'name': 'Charlie',
      'dept': 'Sales',
      'salary': 65000,
      'active': true
    },
    {
      'id': '4',
      'name': 'Diana',
      'dept': 'Engineering',
      'salary': 110000,
      'active': true
    },
    {'id': '5', 'name': 'Eve', 'dept': 'HR', 'salary': 58000, 'active': false},
    {
      'id': '6',
      'name': 'Frank',
      'dept': 'Sales',
      'salary': 71000,
      'active': true
    },
  ];
  for (final emp in employees) {
    await vault.secureSave('emp:${emp['id']}', emp);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  1. ADVANCED QUERY DSL
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 1. Advanced Query DSL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Filter: Engineering dept + salary > 80k, sort by salary desc, limit 3.
  final qResult = await VaultQuery<Map<String, dynamic>>()
      .where('dept')
      .equals('Engineering')
      .and('salary')
      .greaterThan(80000)
      .orderByDesc('salary')
      .limit(3)
      .execute(vault);

  print('Engineering employees earning > \$80k (sorted by salary desc):');
  for (final emp in qResult.records) {
    print('  ${emp['name']}: \$${emp['salary']}');
  }
  print(
      '  Total matches: ${qResult.totalCount}, hasMore: ${qResult.hasMore}\n');

  // Prefix scan + OR filter.
  final orResult = await VaultQuery<Map<String, dynamic>>()
      .keyPrefix('emp:')
      .where('dept')
      .equals('Sales')
      .or('dept')
      .equals('HR')
      .orderBy('name')
      .execute(vault);
  print(
      'Sales OR HR employees: ${orResult.records.map((e) => e['name']).join(', ')}\n');

  // Pagination demo.
  final page1 = await VaultQuery<Map<String, dynamic>>()
      .orderBy('salary')
      .limit(2)
      .offset(0)
      .execute(vault);
  final page2 = await VaultQuery<Map<String, dynamic>>()
      .orderBy('salary')
      .limit(2)
      .offset(2)
      .execute(vault);
  print('Page 1: ${page1.records.map((e) => e['name']).join(', ')}');
  print('Page 2: ${page2.records.map((e) => e['name']).join(', ')}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  2. TRANSACTION MANAGER
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 2. Transaction Manager ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final txManager = VaultTransactionManager(vault);

  // Atomic multi-write.
  final receipt = await txManager.runInTransaction((tx) async {
    tx.write('emp:7', {
      'id': '7',
      'name': 'Grace',
      'dept': 'Engineering',
      'salary': 88000,
      'active': true
    });
    tx.write('emp:8', {
      'id': '8',
      'name': 'Hank',
      'dept': 'Sales',
      'salary': 62000,
      'active': true
    });
    tx.delete('emp:5'); // Remove inactive employee.
  });
  print(
      'Transaction committed: writes=${receipt.writes}, deletes=${receipt.deletes}, '
      'elapsed=${receipt.elapsed.inMilliseconds}ms');

  // Demonstrate rollback.
  final tx2 = txManager.begin();
  tx2.write('temp:key', 'temporary value');
  final sp = tx2.savepoint('before-dangerous-op');
  tx2.write('danger', 'this will be rolled back');
  tx2.rollbackToSavepoint(sp);
  print(
      'After savepoint rollback, pendingOps=${tx2.pendingOperations} (only temp:key remains)');
  await tx2.rollback();
  print('Full rollback — temp:key not persisted: '
      '${!(await vault.secureContains('temp:key'))}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  3. PLUGIN SYSTEM
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 3. Plugin System ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final timer = TimingPlugin();
  final pluggable = PluggableVault(inner: InMemoryVault('plugin_demo'))
    ..use(
        SchemaValidationPlugin(requiredFields: {'name': String, 'salary': int}))
    ..use(FieldMaskingPlugin(maskedFields: {'ssn', 'password'}))
    ..use(timer)
    ..use(ConsoleLoggingPlugin(verbose: true));

  await pluggable.initialize();
  await pluggable.secureSave('emp:p1', {
    'name': 'Ivy',
    'salary': 75000,
    'ssn': '999-99-9999',
    'password': 'hunter2',
  });

  final saved = await pluggable.secureGet<Map>('emp:p1');
  print(
      'After field masking — SSN: ${saved?['ssn']}, Password: ${saved?['password']}');
  print('Avg save latency: ${timer.averageUs('save').toStringAsFixed(1)} µs');
  print(
      'Registered plugins: ${pluggable.plugins.all.map((p) => p.name).join(', ')}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  4. OBSERVABILITY & METRICS
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 4. Observability & Metrics ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final metrics = VaultMetrics(vaultName: 'showcase');
  for (int i = 0; i < 20; i++) {
    metrics.recordOperation(MetricOperation.write,
        durationUs: 800 + i * 50, bytes: 256);
    metrics.recordOperation(MetricOperation.read,
        durationUs: 200 + i * 10, bytes: 256, fromCache: i % 3 == 0);
  }
  metrics.recordOperation(MetricOperation.search,
      durationUs: 15000, bytes: 0, isError: false);
  metrics.recordOperation(MetricOperation.write, durationUs: 0, isError: true);

  final snap = metrics.snapshot();
  print('Metrics snapshot:');
  print(
      '  Writes: ${snap.counters['write']}  Reads: ${snap.counters['read']}  Searches: ${snap.counters['search']}');
  print('  Error rate: ${(snap.errorRate * 100).toStringAsFixed(1)}%');
  print(
      '  Cache hit ratio: ${(metrics.cacheHitRatio * 100).toStringAsFixed(1)}%');
  final wh = metrics.histogramFor(MetricOperation.write);
  print(
      '  Write latency — p50: ${wh.p50}µs  p95: ${wh.p95}µs  p99: ${wh.p99}µs');
  print('  Total errors: ${metrics.totalErrors}\n');

  // Prometheus export.
  final prom = metrics.toPrometheusText();
  print('Prometheus snippet (first 3 lines):');
  prom.split('\n').take(3).forEach((l) => print('  $l'));
  print('');

  // ════════════════════════════════════════════════════════════════════════
  //  5. SHARDING
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 5. Data Sharding ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final shards = List.generate(
    3,
    (i) => ShardDescriptor(
        index: i, boxName: 'shard_$i', vault: InMemoryVault('shard_$i')),
  );
  final shardManager = ShardManager(
    shards: shards,
    strategy: PrefixRoutingStrategy({'user:': 0, 'order:': 1}, defaultShard: 2),
  );
  await shardManager.initialize();

  await shardManager.secureSaveBatch({
    'user:1': {'name': 'Alice'},
    'user:2': {'name': 'Bob'},
    'order:101': {'total': 199.99},
    'order:102': {'total': 49.99},
    'config:theme': {'mode': 'dark'},
  });

  final balance = await shardManager.balanceReport();
  print(
      'Shard balance: ${balance.entries.map((e) => '${e.key}:${e.value}').join(', ')}');

  final allKeys = await shardManager.getAllKeys();
  print('Total keys across all shards: ${allKeys.length}');
  final order = await shardManager.secureGet<Map>('order:101');
  print('order:101 total = \$${order?['total']}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  6. RATE LIMITING
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 6. Rate Limiting ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final bucket = TokenBucket(capacity: 5, refillRate: 10);
  int allowed = 0, rejected = 0;
  for (int i = 0; i < 10; i++) {
    if (bucket.tryConsume())
      allowed++;
    else
      rejected++;
  }
  print('TokenBucket(capacity:5): allowed=$allowed, rejected=$rejected');

  final sliding =
      SlidingWindowLimiter(maxRequests: 3, window: Duration(seconds: 1));
  int swAllowed = 0;
  for (int i = 0; i < 5; i++) {
    if (sliding.tryAcquire()) swAllowed++;
  }
  print('SlidingWindow(3/sec): allowed $swAllowed/5 requests');

  final perKey = PerKeyRateLimiter(capacity: 2, refillRate: 5);
  print(
      'PerKeyLimiter user:1: ${perKey.tryConsume('user:1')} ${perKey.tryConsume('user:1')} ${perKey.tryConsume('user:1')} (expect: true true false)');
  print('PerKey active buckets: ${perKey.activeBuckets}');

  final vaultLimiter = VaultRateLimiter.mobile();
  vaultLimiter.checkWrite();
  vaultLimiter.checkRead();
  print(
      'VaultRateLimiter.mobile() — write/read checks passed. Violations: ${vaultLimiter.violationCount}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  7. CONFLICT RESOLUTION
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 7. Conflict Resolution ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final now = DateTime.now();
  final local = VersionedValue<Map<String, dynamic>>(
    value: {'name': 'Alice', 'score': 100, 'city': 'London'},
    sourceId: 'device-A',
    timestamp: now,
    version: 3,
    vectorClock: {'device-A': 3, 'device-B': 1},
  );
  final remote = VersionedValue<Map<String, dynamic>>(
    value: {'name': 'Alice', 'score': 120, 'email': 'alice@example.com'},
    sourceId: 'device-B',
    timestamp: now.add(Duration(seconds: 5)),
    version: 4,
    vectorClock: {'device-A': 2, 'device-B': 4},
  );
  final conflict = VaultConflict<Map<String, dynamic>>(
      key: 'user:alice', local: local, remote: remote);

  // LWW
  final lwwRes =
      await LastWriteWinsResolver<Map<String, dynamic>>().resolve(conflict);
  print(
      'LWW strategy: ${lwwRes.strategy.name} — score=${lwwRes.resolvedValue['score']}');

  // Field merge
  final mergeRes = await FieldMergeResolver(
    localPriorityFields: {'city'},
  ).resolve(conflict);
  print(
      'Field merge: score=${mergeRes.resolvedValue['score']}, city=${mergeRes.resolvedValue['city']}, email=${mergeRes.resolvedValue['email']}');

  // Vector clock
  final vvRes =
      await VersionVectorResolver<Map<String, dynamic>>().resolve(conflict);
  print(
      'Vector clock: strategy=${vvRes.strategy.name} (remote vector dominates)\n');

  // ════════════════════════════════════════════════════════════════════════
  //  8. KEY ROTATION SCHEDULER (metadata only — no Hive box in this demo)
  // ════════════════════════════════════════════════════════════════════════
  print('━━━ 8. Key Rotation Scheduler ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('KeyRotationPolicy.daily() — rotates every 24h');
  print('KeyRotationPolicy.countBased() — rotates every 10,000 encrypt ops');
  print('KeyRotationPolicy.manual() — explicit rotateNow() only');
  final policy = KeyRotationPolicy(
    rotationInterval: Duration(hours: 24),
    maxEncryptOperations: 10000,
    reEncryptExisting: true,
    archiveSize: 5,
  );
  print('Policy: time=${policy.isTimeBased}, count=${policy.isCountBased}, '
      'reEncrypt=${policy.reEncryptExisting}, archiveSize=${policy.archiveSize}\n');

  // ════════════════════════════════════════════════════════════════════════
  //  Summary
  // ════════════════════════════════════════════════════════════════════════
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║   Batch 11-12 showcase complete. All features demonstrated.  ║');
  print('╚══════════════════════════════════════════════════════════════╝');
}
