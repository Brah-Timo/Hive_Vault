// test/performance/search_benchmark.dart
// ─────────────────────────────────────────────────────────────────────────────
// Performance benchmarks for the in-memory index engine.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('Index Search Benchmarks', () {
    late InMemoryIndexEngine engine;

    setUp(() {
      engine = InMemoryIndexEngine(const IndexingConfig(
        enableAutoIndexing: true,
        minimumTokenLength: 2,
        maxTokensPerEntry: 50,
        enablePrefixSearch: true,
      ));
    });

    void _populateEngine(int count) {
      for (int i = 0; i < count; i++) {
        engine.indexEntry(
          'KEY-$i',
          'Invoice $i client Ahmed Mohamed amount ${i * 100} '
          'product item category sector region',
        );
      }
    }

    void _benchSearch(int entryCount, String query, String mode) {
      _populateEngine(entryCount);

      const runs = 1000;
      final times = <int>[];

      for (int i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        switch (mode) {
          case 'AND':
            engine.searchAll(query);
            break;
          case 'OR':
            engine.searchAny(query);
            break;
          case 'PREFIX':
            engine.searchPrefix(query);
            break;
        }
        times.add(sw.elapsedMicroseconds);
      }

      final avg = times.reduce((a, b) => a + b) / runs;
      final max = times.reduce((a, b) => a > b ? a : b);

      print(
        '  [$mode] $entryCount entries | '
        'avg: ${avg.toStringAsFixed(1)} µs | '
        'max: $max µs',
      );

      expect(avg, lessThan(1000),
          reason: 'Index search should average < 1ms for $entryCount entries');
    }

    test('AND search — 100 entries', () {
      _benchSearch(100, 'ahmed invoice', 'AND');
    });

    test('AND search — 1,000 entries', () {
      _benchSearch(1000, 'ahmed invoice', 'AND');
    });

    test('AND search — 10,000 entries', () {
      _benchSearch(10000, 'ahmed invoice', 'AND');
    });

    test('AND search — 50,000 entries', () {
      _benchSearch(50000, 'ahmed invoice', 'AND');
    });

    test('OR search — 10,000 entries', () {
      _benchSearch(10000, 'ahmed mohamed', 'OR');
    });

    test('PREFIX search — 10,000 entries', () {
      _benchSearch(10000, 'inv', 'PREFIX');
    });

    test('index rebuild — 1,000 entries', () {
      const count = 1000;
      final corpus = {
        for (int i = 0; i < count; i++)
          'KEY-$i': 'Invoice $i client $i region $i',
      };
      final sw = Stopwatch()..start();
      engine.rebuildFrom(corpus);
      sw.stop();
      print(
        '  Rebuild $count entries: ${sw.elapsedMilliseconds} ms',
      );
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });
}
