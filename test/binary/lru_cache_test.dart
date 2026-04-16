// test/binary/lru_cache_test.dart

import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('LruCache', () {
    test('put and get basic value', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      expect(cache.get('a'), equals(1));
    });

    test('returns null for missing key', () {
      final cache = LruCache<String, int>(maxSize: 3);
      expect(cache.get('missing'), isNull);
    });

    test('evicts least recently used when full', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      // Access 'a' and 'b' to make 'c' the LRU
      cache.get('a');
      cache.get('b');
      // Now insert 'd' — 'c' should be evicted
      cache.put('d', 4);
      expect(cache.get('c'), isNull); // evicted
      expect(cache.get('a'), equals(1));
      expect(cache.get('b'), equals(2));
      expect(cache.get('d'), equals(4));
    });

    test('put updates existing key', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('a', 99);
      expect(cache.get('a'), equals(99));
      expect(cache.length, equals(1));
    });

    test('remove deletes a key', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.remove('a');
      expect(cache.get('a'), isNull);
      expect(cache.length, equals(0));
    });

    test('clear empties the cache', () {
      final cache = LruCache<String, int>(maxSize: 10);
      for (var i = 0; i < 5; i++) cache.put('k$i', i);
      cache.clear();
      expect(cache.isEmpty, isTrue);
    });

    test('capacity is respected', () {
      const max = 5;
      final cache = LruCache<int, int>(maxSize: max);
      for (var i = 0; i < max * 3; i++) cache.put(i, i);
      expect(cache.length, equals(max));
    });

    test('get promotes entry to MRU', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // promote 'a'
      cache.put('c', 3); // 'b' should be evicted (LRU)
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), equals(1));
    });
  });

  group('InstrumentedLruCache', () {
    test('tracks hits and misses correctly', () {
      final cache = InstrumentedLruCache<String, int>(maxSize: 5);
      cache.put('x', 10);
      cache.get('x'); // hit
      cache.get('x'); // hit
      cache.get('y'); // miss
      expect(cache.hits, equals(2));
      expect(cache.misses, equals(1));
    });

    test('resetCounters zeroes hit/miss counts', () {
      final cache = InstrumentedLruCache<String, int>(maxSize: 5);
      cache.put('x', 1);
      cache.get('x');
      cache.get('y');
      cache.resetCounters();
      expect(cache.hits, equals(0));
      expect(cache.misses, equals(0));
    });
  });
}
