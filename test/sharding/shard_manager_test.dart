// test/sharding/shard_manager_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for the ShardManager and routing strategies.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/sharding/shard_manager.dart';

// ── Stub vault ────────────────────────────────────────────────────────────────
import 'dart:typed_data';
import '../../lib/src/core/vault_interface.dart';
import '../../lib/src/core/sensitivity_level.dart';
import '../../lib/src/core/vault_stats.dart';
import '../../lib/src/audit/audit_entry.dart';

class _StubVault implements SecureStorageInterface {
  final String name;
  final Map<String, dynamic> data = {};
  _StubVault(this.name);

  @override Future<void> initialize() async {}
  @override Future<void> close() async {}
  @override Future<bool> secureContains(String k) async => data.containsKey(k);
  @override Future<List<String>> getAllKeys() async => data.keys.toList();
  @override Future<T?> secureGet<T>(String k) async => data[k] as T?;
  @override Future<void> secureDelete(String k) async => data.remove(k);
  @override Future<void> secureSave<T>(String k, T v, {SensitivityLevel? sensitivity, String? searchableText}) async => data[k] = v;
  @override Future<void> secureSaveBatch(Map<String, dynamic> e, {SensitivityLevel? sensitivity}) async => data.addAll(e);
  @override Future<Map<String, dynamic>> secureGetBatch(List<String> ks) async => {for (final k in ks) if (data.containsKey(k)) k: data[k]};
  @override Future<void> secureDeleteBatch(List<String> ks) async => ks.forEach(data.remove);
  @override Future<List<T>> secureSearch<T>(String q) async => [];
  @override Future<List<T>> secureSearchAny<T>(String q) async => [];
  @override Future<List<T>> secureSearchPrefix<T>(String p) async => [];
  @override Future<Set<String>> searchKeys(String q) async => {};
  @override Future<void> rebuildIndex() async {}
  @override Future<void> compact() async {}
  @override void clearCache() {}
  @override Future<Uint8List> exportEncrypted() async => Uint8List(0);
  @override Future<void> importEncrypted(Uint8List d) async {}
  @override Future<VaultStats> getStats() async => VaultStats(boxName: name, totalEntries: data.length, cacheSize: 0, cacheCapacity: 0, cacheHitRatio: 0, compressionAlgorithm: 'None', encryptionAlgorithm: 'None', indexStats: const IndexStats.empty(), totalBytesSaved: 0, totalBytesWritten: 0, totalWrites: 0, totalReads: 0, totalSearches: 0, openedAt: DateTime.now());
  @override List<AuditEntry> getAuditLog({int limit = 50}) => [];
}

List<ShardDescriptor> _makeShards(int count) => List.generate(
      count,
      (i) => ShardDescriptor(
        index: i,
        boxName: 'shard_$i',
        vault: _StubVault('shard_$i'),
      ),
    );

void main() {
  // ── Routing strategies ────────────────────────────────────────────────────

  group('ConsistentHashStrategy', () {
    final s = ConsistentHashStrategy();

    test('same key always routes to same shard', () {
      final idx1 = s.route('user:42', 4);
      final idx2 = s.route('user:42', 4);
      expect(idx1, equals(idx2));
    });

    test('returns index in valid range', () {
      for (final key in ['a', 'b', 'abc', 'user:1', 'order:99']) {
        final idx = s.route(key, 4);
        expect(idx, greaterThanOrEqualTo(0));
        expect(idx, lessThan(4));
      }
    });

    test('distributes keys across shards (no single shard gets all)', () {
      final counts = List.filled(4, 0);
      for (int i = 0; i < 100; i++) {
        counts[s.route('key$i', 4)]++;
      }
      // Each shard should get at least 1 key out of 100.
      expect(counts.every((c) => c > 0), isTrue);
    });
  });

  group('PrefixRoutingStrategy', () {
    final s = PrefixRoutingStrategy({
      'user:': 0,
      'order:': 1,
      'product:': 2,
    }, defaultShard: 3);

    test('routes by prefix', () {
      expect(s.route('user:42', 4), equals(0));
      expect(s.route('order:99', 4), equals(1));
      expect(s.route('product:5', 4), equals(2));
    });

    test('uses defaultShard for unmatched prefixes', () {
      expect(s.route('config:app', 4), equals(3));
    });
  });

  group('ModuloStrategy', () {
    final s = ModuloStrategy();

    test('routes numeric suffix by modulo', () {
      expect(s.route('key0', 4), equals(0));
      expect(s.route('key4', 4), equals(0));
      expect(s.route('key1', 4), equals(1));
    });

    test('returns valid range for non-numeric keys', () {
      final idx = s.route('nodigits', 4);
      expect(idx, greaterThanOrEqualTo(0));
      expect(idx, lessThan(4));
    });
  });

  group('CustomRoutingStrategy', () {
    test('delegates to provided function', () {
      final s = CustomRoutingStrategy((key, count) => key.length % count);
      expect(s.route('ab', 4), equals(2)); // length 2 % 4 = 2
      expect(s.route('abcd', 4), equals(0)); // length 4 % 4 = 0
    });
  });

  // ── ShardManager ──────────────────────────────────────────────────────────

  group('ShardManager', () {
    late ShardManager manager;
    late List<ShardDescriptor> shards;

    setUp(() async {
      shards = _makeShards(4);
      manager = ShardManager(
        shards: shards,
        strategy: PrefixRoutingStrategy({
          'user:': 0,
          'order:': 1,
        }, defaultShard: 2),
      );
      await manager.initialize();
    });

    test('secureSave routes to correct shard', () async {
      await manager.secureSave('user:1', {'name': 'Alice'});
      final shard0 = shards[0].vault as _StubVault;
      expect(shard0.data.containsKey('user:1'), isTrue);
    });

    test('secureGet retrieves from correct shard', () async {
      await manager.secureSave('order:99', {'total': 250.0});
      final result = await manager.secureGet<Map>('order:99');
      expect(result, isNotNull);
      expect((result as Map)['total'], equals(250.0));
    });

    test('secureDelete removes from correct shard', () async {
      await manager.secureSave('user:5', 'data');
      await manager.secureDelete('user:5');
      final shard0 = shards[0].vault as _StubVault;
      expect(shard0.data.containsKey('user:5'), isFalse);
    });

    test('getAllKeys aggregates across all shards', () async {
      await manager.secureSave('user:1', 'u');
      await manager.secureSave('order:2', 'o');
      await manager.secureSave('misc:3', 'm');
      final keys = await manager.getAllKeys();
      expect(keys.length, equals(3));
    });

    test('secureSaveBatch groups by shard', () async {
      await manager.secureSaveBatch({
        'user:10': 'u10',
        'user:11': 'u11',
        'order:20': 'o20',
      });
      final shard0 = shards[0].vault as _StubVault;
      final shard1 = shards[1].vault as _StubVault;
      expect(shard0.data.length, equals(2));
      expect(shard1.data.length, equals(1));
    });

    test('secureGetBatch returns values from multiple shards', () async {
      await manager.secureSave('user:1', 'alice');
      await manager.secureSave('order:1', 'ord1');
      final batch = await manager.secureGetBatch(['user:1', 'order:1']);
      expect(batch['user:1'], equals('alice'));
      expect(batch['order:1'], equals('ord1'));
    });

    test('shardCount matches number of shards', () {
      expect(manager.shardCount, equals(4));
    });

    test('strategyName returns correct name', () {
      expect(manager.strategyName, equals('prefix'));
    });

    test('getShardStats returns per-shard info', () async {
      await manager.secureSave('user:1', 'u');
      final stats = await manager.getShardStats();
      expect(stats.length, equals(4));
      expect(stats[0].entryCount, equals(1));
    });

    test('balanceReport maps shard names to entry counts', () async {
      await manager.secureSave('user:1', 'u');
      final report = await manager.balanceReport();
      expect(report.containsKey('shard_0'), isTrue);
    });
  });
}
