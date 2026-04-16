// lib/src/cache/lru_cache.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Generic LRU (Least-Recently-Used) in-memory cache.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:collection';

/// A generic Least-Recently-Used (LRU) cache with a fixed capacity.
///
/// When the cache is full the least-recently-accessed entry is evicted to
/// make room for the new entry.
///
/// ## Implementation detail
/// Uses [LinkedHashMap] with [accessOrder: true] so that the map's
/// iteration order reflects access order (oldest-access first), allowing O(1)
/// eviction of the LRU entry.
///
/// ## Thread-safety
/// Not thread-safe. All operations are expected to run on the Flutter main
/// isolate where Hive calls are also made.
class LruCache<K, V> {
  /// Maximum number of entries the cache will hold.
  final int capacity;

  late final LinkedHashMap<K, V> _map;

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  LruCache({required this.capacity}) {
    assert(capacity > 0, 'LruCache capacity must be > 0');
    _map = LinkedHashMap<K, V>(
        // No custom hash/equals — uses default Dart equality.
        );
  }

  // ─── Core operations ──────────────────────────────────────────────────────

  /// Returns the value associated with [key], or `null` if not cached.
  ///
  /// A cache hit promotes the entry to "most recently used" position.
  V? get(K key) {
    final value = _map.remove(key);
    if (value == null) {
      _misses++;
      return null;
    }
    // Re-insert to move to tail (most-recently-used position).
    _map[key] = value;
    _hits++;
    return value;
  }

  /// Stores [value] under [key].
  ///
  /// If the cache is at capacity, the least-recently-used entry is evicted
  /// before inserting the new entry.
  void put(K key, V value) {
    _map.remove(key); // Remove existing to update position.
    if (_map.length >= capacity) {
      // Evict the oldest (first) entry.
      _map.remove(_map.keys.first);
      _evictions++;
    }
    _map[key] = value;
  }

  /// Removes the entry for [key] from the cache.
  void remove(K key) => _map.remove(key);

  /// Removes all entries from the cache and resets statistics.
  void clear() {
    _map.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  // ─── Query helpers ────────────────────────────────────────────────────────

  /// Returns `true` if [key] is present in the cache.
  /// Does NOT update the access order — use [get] for read-through caching.
  bool containsKey(K key) => _map.containsKey(key);

  /// Current number of entries in the cache.
  int get length => _map.length;

  /// Returns `true` if the cache contains no entries.
  bool get isEmpty => _map.isEmpty;

  // ─── Statistics ───────────────────────────────────────────────────────────

  /// Total cache hits since creation or last [clear].
  int get hits => _hits;

  /// Total cache misses since creation or last [clear].
  int get misses => _misses;

  /// Total entries evicted since creation or last [clear].
  int get evictions => _evictions;

  /// Hit ratio between 0.0 (no hits) and 1.0 (all hits).
  double get hitRatio {
    final total = _hits + _misses;
    return total == 0 ? 0.0 : _hits / total;
  }

  /// Returns all currently cached keys in LRU order (oldest first).
  Iterable<K> get keys => _map.keys;

  @override
  String toString() => 'LruCache('
      'capacity: $capacity, '
      'size: ${_map.length}, '
      'hits: $_hits, '
      'misses: $_misses, '
      'hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed alias used by HiveVaultImpl for the decrypted-object cache.
// ─────────────────────────────────────────────────────────────────────────────

/// A specialised LRU cache that maps vault keys to their decrypted values.
///
/// Entries are stored as [dynamic] to avoid per-type parameterisation.
typedef VaultCache = LruCache<String, dynamic>;

/// Creates a [VaultCache] from the given [capacity].
VaultCache createVaultCache(int capacity) => LruCache(capacity: capacity);
