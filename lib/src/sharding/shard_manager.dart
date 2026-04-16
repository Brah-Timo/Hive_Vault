// lib/src/sharding/shard_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Data Sharding Manager.
//
// Horizontally partitions vault data across multiple Hive boxes (shards).
// Each key is deterministically routed to a shard via a configurable strategy.
//
// Built-in strategies:
//   • ConsistentHash — MD5-based ring hashing for balanced distribution.
//   • KeyPrefix      — routes based on key prefix (e.g., 'user:' → shard 0).
//   • Modulo         — fast integer modulo for numeric keys.
//   • Custom         — caller-supplied routing function.
//
// Benefits:
//   • Reduces single-box size (Hive has practical size limits on mobile).
//   • Enables per-shard encryption keys and compression settings.
//   • Allows selective compaction of individual shards.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import '../core/vault_interface.dart';
import '../core/vault_exceptions.dart';
import '../core/sensitivity_level.dart';
import '../core/vault_stats.dart';
import '../audit/audit_entry.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Shard routing strategy
// ═══════════════════════════════════════════════════════════════════════════

/// Determines which shard a given key belongs to.
abstract class ShardRoutingStrategy {
  /// Returns the shard index (0-based) for [key].
  int route(String key, int shardCount);

  String get name;
}

/// Consistent-hash routing using a simple polynomial hash.
class ConsistentHashStrategy implements ShardRoutingStrategy {
  @override
  String get name => 'consistent_hash';

  @override
  int route(String key, int shardCount) {
    // DJB2-inspired hash for even distribution.
    int hash = 5381;
    for (final rune in key.runes) {
      hash = ((hash << 5) + hash) ^ rune;
      hash &= 0x7FFFFFFF; // Keep positive 31-bit integer.
    }
    return hash % shardCount;
  }
}

/// Prefix-based routing: maps key prefixes to specific shards.
///
/// Example:
/// ```dart
/// PrefixRoutingStrategy({
///   'user:': 0,
///   'order:': 1,
///   'product:': 2,
/// }, defaultShard: 3)
/// ```
class PrefixRoutingStrategy implements ShardRoutingStrategy {
  final Map<String, int> prefixMap;
  final int defaultShard;

  const PrefixRoutingStrategy(this.prefixMap, {this.defaultShard = 0});

  @override
  String get name => 'prefix';

  @override
  int route(String key, int shardCount) {
    for (final entry in prefixMap.entries) {
      if (key.startsWith(entry.key)) {
        return entry.value.clamp(0, shardCount - 1);
      }
    }
    return defaultShard.clamp(0, shardCount - 1);
  }
}

/// Modulo routing — fast, deterministic for numeric key suffixes.
class ModuloStrategy implements ShardRoutingStrategy {
  @override
  String get name => 'modulo';

  @override
  int route(String key, int shardCount) {
    // Extract trailing digits from the key if present.
    final digits = RegExp(r'\d+$').firstMatch(key)?.group(0);
    if (digits != null) {
      return int.parse(digits) % shardCount;
    }
    // Fall back to character-sum modulo.
    final sum = key.codeUnits.fold<int>(0, (a, b) => a + b);
    return sum % shardCount;
  }
}

/// Custom routing via a user-supplied function.
class CustomRoutingStrategy implements ShardRoutingStrategy {
  final int Function(String key, int shardCount) _fn;
  @override
  final String name;

  CustomRoutingStrategy(this._fn, {this.name = 'custom'});

  @override
  int route(String key, int shardCount) => _fn(key, shardCount);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shard descriptor
// ═══════════════════════════════════════════════════════════════════════════

/// Metadata about a single shard.
class ShardDescriptor {
  final int index;
  final String boxName;
  final SecureStorageInterface vault;

  const ShardDescriptor({
    required this.index,
    required this.boxName,
    required this.vault,
  });

  @override
  String toString() => 'Shard(index: $index, box: $boxName)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shard statistics
// ═══════════════════════════════════════════════════════════════════════════

/// Per-shard stats as reported by [ShardManager.getShardStats].
class ShardStats {
  final int shardIndex;
  final String boxName;
  final int entryCount;
  final int readOps;
  final int writeOps;

  const ShardStats({
    required this.shardIndex,
    required this.boxName,
    required this.entryCount,
    required this.readOps,
    required this.writeOps,
  });

  @override
  String toString() => 'ShardStats(index: $shardIndex, box: $boxName, '
      'entries: $entryCount, reads: $readOps, writes: $writeOps)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shard Manager (implements SecureStorageInterface)
// ═══════════════════════════════════════════════════════════════════════════

/// Routes vault operations across multiple underlying vault instances (shards).
///
/// Presents a single [SecureStorageInterface] to callers while distributing
/// data across [shards] based on [strategy].
///
/// ```dart
/// final manager = ShardManager(
///   shards: [shard0, shard1, shard2, shard3],
///   strategy: PrefixRoutingStrategy({
///     'user:': 0, 'order:': 1, 'product:': 2,
///   }, defaultShard: 3),
/// );
/// await manager.initialize();
/// await manager.secureSave('user:42', userData);
/// ```
class ShardManager implements SecureStorageInterface {
  final List<ShardDescriptor> _shards;
  final ShardRoutingStrategy _strategy;

  // Per-shard operation counters for diagnostics.
  final List<int> _readCounts;
  final List<int> _writeCounts;

  bool _initialized = false;

  ShardManager({
    required List<ShardDescriptor> shards,
    ShardRoutingStrategy? strategy,
  })  : _shards = shards,
        _strategy = strategy ?? ConsistentHashStrategy(),
        _readCounts = List.filled(shards.length, 0),
        _writeCounts = List.filled(shards.length, 0) {
    assert(shards.isNotEmpty, 'ShardManager requires at least one shard');
  }

  // ── Routing ───────────────────────────────────────────────────────────────

  SecureStorageInterface _shardFor(String key) {
    final idx = _strategy.route(key, _shards.length);
    return _shards[idx].vault;
  }

  int _shardIndexFor(String key) => _strategy.route(key, _shards.length);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    for (final shard in _shards) {
      await shard.vault.initialize();
    }
    _initialized = true;
  }

  @override
  Future<void> close() async {
    for (final shard in _shards) {
      await shard.vault.close();
    }
    _initialized = false;
  }

  // ── Core CRUD ─────────────────────────────────────────────────────────────

  @override
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  }) async {
    final idx = _shardIndexFor(key);
    _writeCounts[idx]++;
    await _shards[idx].vault.secureSave(
          key,
          value,
          sensitivity: sensitivity,
          searchableText: searchableText,
        );
  }

  @override
  Future<T?> secureGet<T>(String key) async {
    final idx = _shardIndexFor(key);
    _readCounts[idx]++;
    return _shards[idx].vault.secureGet<T>(key);
  }

  @override
  Future<void> secureDelete(String key) async {
    final idx = _shardIndexFor(key);
    await _shards[idx].vault.secureDelete(key);
  }

  @override
  Future<bool> secureContains(String key) async =>
      _shardFor(key).secureContains(key);

  @override
  Future<List<String>> getAllKeys() async {
    final allKeys = <String>[];
    for (final shard in _shards) {
      allKeys.addAll(await shard.vault.getAllKeys());
    }
    return allKeys;
  }

  // ── Batch operations ──────────────────────────────────────────────────────

  @override
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  }) async {
    // Group entries by shard.
    final groups = <int, Map<String, dynamic>>{};
    for (final entry in entries.entries) {
      final idx = _shardIndexFor(entry.key);
      (groups[idx] ??= {})[entry.key] = entry.value;
    }
    for (final group in groups.entries) {
      await _shards[group.key].vault.secureSaveBatch(
            group.value,
            sensitivity: sensitivity,
          );
    }
  }

  @override
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys) async {
    final groups = <int, List<String>>{};
    for (final key in keys) {
      (groups[_shardIndexFor(key)] ??= []).add(key);
    }
    final result = <String, dynamic>{};
    for (final group in groups.entries) {
      final batch = await _shards[group.key].vault.secureGetBatch(group.value);
      result.addAll(batch);
    }
    return result;
  }

  @override
  Future<void> secureDeleteBatch(List<String> keys) async {
    final groups = <int, List<String>>{};
    for (final key in keys) {
      (groups[_shardIndexFor(key)] ??= []).add(key);
    }
    for (final group in groups.entries) {
      await _shards[group.key].vault.secureDeleteBatch(group.value);
    }
  }

  // ── Search (fan-out across all shards) ───────────────────────────────────

  @override
  Future<List<T>> secureSearch<T>(String query) async {
    final results = <T>[];
    for (final shard in _shards) {
      results.addAll(await shard.vault.secureSearch<T>(query));
    }
    return results;
  }

  @override
  Future<List<T>> secureSearchAny<T>(String query) async {
    final results = <T>[];
    for (final shard in _shards) {
      results.addAll(await shard.vault.secureSearchAny<T>(query));
    }
    return results;
  }

  @override
  Future<List<T>> secureSearchPrefix<T>(String prefix) async {
    final results = <T>[];
    for (final shard in _shards) {
      results.addAll(await shard.vault.secureSearchPrefix<T>(prefix));
    }
    return results;
  }

  @override
  Future<Set<String>> searchKeys(String query) async {
    final results = <String>{};
    for (final shard in _shards) {
      results.addAll(await shard.vault.searchKeys(query));
    }
    return results;
  }

  // ── Maintenance ───────────────────────────────────────────────────────────

  @override
  Future<void> rebuildIndex() async {
    for (final shard in _shards) {
      await shard.vault.rebuildIndex();
    }
  }

  @override
  Future<void> compact() async {
    for (final shard in _shards) {
      await shard.vault.compact();
    }
  }

  /// Compact a single shard by index.
  Future<void> compactShard(int index) async {
    assert(index >= 0 && index < _shards.length, 'Invalid shard index');
    await _shards[index].vault.compact();
  }

  @override
  void clearCache() {
    for (final shard in _shards) {
      shard.vault.clearCache();
    }
  }

  // ── Import/Export ─────────────────────────────────────────────────────────

  @override
  Future<Uint8List> exportEncrypted() async {
    // Export all shards and concatenate JSON.
    final exports = <String, String>{};
    for (int i = 0; i < _shards.length; i++) {
      final data = await _shards[i].vault.exportEncrypted();
      exports['shard_$i'] = base64.encode(data);
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(exports)));
  }

  @override
  Future<void> importEncrypted(Uint8List data) async {
    // Detect if this is a sharded export.
    try {
      final str = utf8.decode(data);
      final map = jsonDecode(str) as Map<String, dynamic>;
      for (int i = 0; i < _shards.length; i++) {
        final key = 'shard_$i';
        if (map.containsKey(key)) {
          final shardData = base64.decode(map[key] as String);
          await _shards[i].vault.importEncrypted(Uint8List.fromList(shardData));
        }
      }
    } catch (_) {
      // Fall back to importing into shard 0.
      await _shards[0].vault.importEncrypted(data);
    }
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  @override
  Future<VaultStats> getStats() async => _shards[0].vault.getStats();

  @override
  List<AuditEntry> getAuditLog({int limit = 50}) =>
      _shards[0].vault.getAuditLog(limit: limit);

  /// Returns per-shard statistics.
  Future<List<ShardStats>> getShardStats() async {
    final stats = <ShardStats>[];
    for (int i = 0; i < _shards.length; i++) {
      final vs = await _shards[i].vault.getStats();
      stats.add(ShardStats(
        shardIndex: i,
        boxName: _shards[i].boxName,
        entryCount: vs.totalEntries,
        readOps: _readCounts[i],
        writeOps: _writeCounts[i],
      ));
    }
    return stats;
  }

  /// Returns the distribution of keys per shard (balance report).
  Future<Map<String, int>> balanceReport() async {
    final report = <String, int>{};
    for (int i = 0; i < _shards.length; i++) {
      final vs = await _shards[i].vault.getStats();
      report[_shards[i].boxName] = vs.totalEntries;
    }
    return report;
  }

  int get shardCount => _shards.length;
  String get strategyName => _strategy.name;
}
