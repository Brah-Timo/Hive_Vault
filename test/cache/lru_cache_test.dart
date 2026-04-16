// test/cache/lru_cache_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for LruCache.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('LruCache', () {
    late LruCache<String, String> cache;

    setUp(() => cache = LruCache(capacity: 3));

    // ── Basic operations ──────────────────────────────────────────────────

    test('put and get a value', () {
      cache.put('k1', 'v1');
      expect(cache.get('k1'), equals('v1'));
    });

    test('get returns null for missing key', () {
      expect(cache.get('missing'), isNull);
    });

    test('length reflects number of entries', () {
      cache.put('a', '1');
      cache.put('b', '2');
      expect(cache.length, equals(2));
    });

    test('containsKey returns true for cached key', () {
      cache.put('x', 'y');
      expect(cache.containsKey('x'), isTrue);
    });

    test('containsKey returns false for missing key', () {
      expect(cache.containsKey('none'), isFalse);
    });

    // ── Capacity / eviction ───────────────────────────────────────────────

    test('evicts LRU entry when at capacity', () {
      cache.put('a', '1');
      cache.put('b', '2');
      cache.put('c', '3');
      // Access 'a' and 'b' so 'c' becomes LRU.
      cache.get('a');
      cache.get('b');
      // Adding 'd' should evict 'c'.
      cache.put('d', '4');
      expect(cache.get('c'), isNull, reason: '"c" should have been evicted');
      expect(cache.get('a'), equals('1'));
      expect(cache.get('b'), equals('2'));
      expect(cache.get('d'), equals('4'));
    });

    test('get promotes entry to most-recently-used position', () {
      cache.put('a', '1');
      cache.put('b', '2');
      cache.put('c', '3');
      // Access 'a' — now LRU is 'b'.
      cache.get('a');
      // Add 'd' — 'b' should be evicted.
      cache.put('d', '4');
      expect(cache.get('b'), isNull, reason: '"b" is now LRU and should evict');
    });

    test('overwrite keeps entry but refreshes position', () {
      cache.put('a', 'original');
      cache.put('b', 'b');
      cache.put('c', 'c');
      cache.put('a', 'updated'); // Re-insert 'a' → a becomes MRU
      cache.put('d', 'd');       // Should evict 'b' (now LRU)
      expect(cache.get('a'), equals('updated'));
      expect(cache.get('b'), isNull);
    });

    // ── Remove ────────────────────────────────────────────────────────────

    test('remove deletes entry', () {
      cache.put('x', 'val');
      cache.remove('x');
      expect(cache.get('x'), isNull);
      expect(cache.length, equals(0));
    });

    test('remove non-existent key is a no-op', () {
      cache.remove('ghost'); // should not throw
    });

    // ── Clear ─────────────────────────────────────────────────────────────

    test('clear empties the cache', () {
      cache.put('a', '1');
      cache.put('b', '2');
      cache.clear();
      expect(cache.isEmpty, isTrue);
      expect(cache.length, equals(0));
    });

    test('clear resets statistics', () {
      cache.put('a', '1');
      cache.get('a'); // hit
      cache.get('b'); // miss
      cache.clear();
      expect(cache.hits, equals(0));
      expect(cache.misses, equals(0));
    });

    // ── Statistics ────────────────────────────────────────────────────────

    test('tracks hits and misses', () {
      cache.put('k', 'v');
      cache.get('k'); // hit
      cache.get('k'); // hit
      cache.get('x'); // miss
      expect(cache.hits, equals(2));
      expect(cache.misses, equals(1));
    });

    test('hitRatio is correct', () {
      cache.put('a', '1');
      cache.get('a'); // hit
      cache.get('a'); // hit
      cache.get('b'); // miss
      // ratio = 2 / 3
      expect(cache.hitRatio, closeTo(2 / 3, 0.001));
    });

    test('hitRatio is 0.0 when no operations', () {
      expect(cache.hitRatio, equals(0.0));
    });

    test('tracks evictions', () {
      cache.put('a', '1');
      cache.put('b', '2');
      cache.put('c', '3');
      cache.put('d', '4'); // 1 eviction
      cache.put('e', '5'); // 2 evictions
      expect(cache.evictions, equals(2));
    });

    // ── Edge cases ────────────────────────────────────────────────────────

    test('capacity of 1 works correctly', () {
      final tiny = LruCache<String, String>(capacity: 1);
      tiny.put('a', 'A');
      tiny.put('b', 'B'); // evicts 'a'
      expect(tiny.get('a'), isNull);
      expect(tiny.get('b'), equals('B'));
    });

    test('capacity assertion fails for 0', () {
      expect(
        () => LruCache<String, String>(capacity: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
