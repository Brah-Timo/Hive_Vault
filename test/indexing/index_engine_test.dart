// test/indexing/index_engine_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for InMemoryIndexEngine and Tokenizer.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────

  InMemoryIndexEngine _makeEngine() {
    return InMemoryIndexEngine(const IndexingConfig(
      enableAutoIndexing: true,
      minimumTokenLength: 2,
      maxTokensPerEntry: 100,
      enablePrefixSearch: true,
      stopWords: {'and', 'or', 'the', 'in'},
    ));
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  Tokenizer tests
  // ════════════════════════════════════════════════════════════════════════════

  group('Tokenizer', () {
    late Tokenizer tokenizer;

    setUp(() {
      tokenizer = Tokenizer(const IndexingConfig(
        minimumTokenLength: 2,
        stopWords: {'and', 'or', 'the'},
      ));
    });

    test('tokenizes basic Latin text', () {
      final tokens = tokenizer.tokenize('Hello World Test');
      expect(tokens, containsAll(['hello', 'world', 'test']));
    });

    test('tokenizes Arabic text', () {
      final tokens = tokenizer.tokenize('أحمد مقرادجي قسنطينة');
      expect(tokens, containsAll(['أحمد', 'مقرادجي', 'قسنطينة']));
    });

    test('tokenizes mixed Arabic-Latin', () {
      final tokens = tokenizer.tokenize('Invoice INV-001 فاتورة أحمد');
      expect(tokens.length, greaterThanOrEqualTo(3));
    });

    test('filters tokens shorter than minimumTokenLength', () {
      final tokens = tokenizer.tokenize('a bb ccc dddd');
      expect(tokens, isNot(contains('a')));
      expect(tokens, contains('bb'));
      expect(tokens, contains('ccc'));
    });

    test('removes stop-words', () {
      final tokens = tokenizer.tokenize('the quick and the brown fox');
      expect(tokens, isNot(contains('the')));
      expect(tokens, isNot(contains('and')));
      expect(tokens, contains('quick'));
    });

    test('removes Arabic diacritics', () {
      // "Ahmed" with harakat → should normalise to same as without.
      final withHarakat = tokenizer.tokenize('أَحْمَد');
      final without = tokenizer.tokenize('أحمد');
      // Both should produce the same normalised token.
      expect(withHarakat.first, equals(without.first));
    });

    test('empty string returns empty set', () {
      expect(tokenizer.tokenize(''), isEmpty);
    });

    test('whitespace-only string returns empty set', () {
      expect(tokenizer.tokenize('   \t\n   '), isEmpty);
    });

    test('caps tokens at maxTokensPerEntry', () {
      final longText = List.generate(200, (i) => 'word$i').join(' ');
      final limited = Tokenizer(const IndexingConfig(maxTokensPerEntry: 50));
      expect(limited.tokenize(longText).length, lessThanOrEqualTo(50));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  InMemoryIndexEngine tests
  // ════════════════════════════════════════════════════════════════════════════

  group('InMemoryIndexEngine', () {
    late InMemoryIndexEngine engine;

    setUp(() => engine = _makeEngine());

    // ── indexEntry ────────────────────────────────────────────────────────

    test('indexEntry adds entry to the index', () {
      engine.indexEntry('KEY-1', 'Ahmed invoice 2026');
      expect(engine.isIndexed('KEY-1'), isTrue);
    });

    test('indexing multiple entries', () {
      engine.indexEntry('INV-001', 'Ahmed invoice January 2026');
      engine.indexEntry('INV-002', 'Mohamed invoice February 2026');
      engine.indexEntry('CLI-001', 'Ahmed client Algiers');
      expect(engine.indexedCount, equals(3));
    });

    test('re-indexing an existing key replaces old tokens', () {
      engine.indexEntry('KEY-1', 'original text');
      engine.indexEntry('KEY-1', 'updated content');
      // Should NOT find 'original' anymore.
      expect(engine.searchAll('original'), isEmpty);
      expect(engine.searchAll('updated'), contains('KEY-1'));
    });

    // ── searchAll (AND) ───────────────────────────────────────────────────

    test('searchAll: single token finds correct entry', () {
      engine.indexEntry('INV-001', 'Ahmed Mekraji invoice');
      engine.indexEntry('INV-002', 'Mohamed Djelloul invoice');
      final results = engine.searchAll('Ahmed');
      expect(results, equals({'INV-001'}));
    });

    test('searchAll: multiple tokens (AND) — returns intersection', () {
      engine.indexEntry('INV-001', 'Ahmed invoice 2026');
      engine.indexEntry('INV-002', 'Ahmed receipt 2025');
      engine.indexEntry('INV-003', 'Mohamed invoice 2026');
      // Only INV-001 has both "Ahmed" AND "invoice"
      final results = engine.searchAll('Ahmed invoice');
      expect(results, equals({'INV-001'}));
    });

    test('searchAll: returns empty for non-existent token', () {
      engine.indexEntry('A', 'hello world');
      expect(engine.searchAll('nonexistent'), isEmpty);
    });

    test('searchAll: returns empty for empty query', () {
      engine.indexEntry('A', 'hello world');
      expect(engine.searchAll(''), isEmpty);
    });

    test('searchAll: AND with one non-matching token returns empty', () {
      engine.indexEntry('A', 'hello world');
      expect(engine.searchAll('hello xyz'), isEmpty);
    });

    // ── searchAny (OR) ────────────────────────────────────────────────────

    test('searchAny: returns union of matches', () {
      engine.indexEntry('INV-001', 'Ahmed invoice');
      engine.indexEntry('INV-002', 'Mohamed receipt');
      engine.indexEntry('INV-003', 'Karim voucher');
      final results = engine.searchAny('Ahmed Mohamed');
      expect(results, containsAll(['INV-001', 'INV-002']));
      expect(results, isNot(contains('INV-003')));
    });

    // ── searchPrefix ──────────────────────────────────────────────────────

    test('searchPrefix: finds entries with prefix match', () {
      engine.indexEntry('CLI-001', 'Ahmed Mekraji Constantine');
      engine.indexEntry('CLI-002', 'Ahlem Boudiaf Algiers');
      engine.indexEntry('CLI-003', 'Karim Bouzid Oran');
      final results = engine.searchPrefix('Ah');
      expect(results, containsAll(['CLI-001', 'CLI-002']));
      expect(results, isNot(contains('CLI-003')));
    });

    test('searchPrefix: empty prefix returns empty set', () {
      engine.indexEntry('A', 'hello world');
      expect(engine.searchPrefix(''), isEmpty);
    });

    // ── removeEntry ───────────────────────────────────────────────────────

    test('removeEntry: removed key no longer appears in search', () {
      engine.indexEntry('KEY-1', 'Ahmed invoice');
      engine.indexEntry('KEY-2', 'Ahmed client');
      engine.removeEntry('KEY-1');
      expect(engine.searchAll('Ahmed'), equals({'KEY-2'}));
      expect(engine.isIndexed('KEY-1'), isFalse);
    });

    test('removeEntry: removing non-existent key is a no-op', () {
      engine.removeEntry('ghost-key'); // should not throw
      expect(engine.indexedCount, equals(0));
    });

    // ── clearIndex ────────────────────────────────────────────────────────

    test('clearIndex: empties the index', () {
      engine.indexEntry('A', 'test');
      engine.indexEntry('B', 'hello');
      engine.clearIndex();
      expect(engine.isEmpty, isTrue);
      expect(engine.indexedCount, equals(0));
    });

    // ── allKeys ───────────────────────────────────────────────────────────

    test('allKeys returns all indexed keys', () {
      engine.indexEntry('K1', 'foo');
      engine.indexEntry('K2', 'bar');
      expect(engine.allKeys(), containsAll(['K1', 'K2']));
    });

    // ── rebuildFrom ───────────────────────────────────────────────────────

    test('rebuildFrom: rebuilds index correctly from corpus', () {
      engine.indexEntry('OLD', 'should be gone');
      engine.rebuildFrom({
        'INV-001': 'Ahmed invoice',
        'INV-002': 'Mohamed invoice',
      });
      expect(engine.isIndexed('OLD'), isFalse);
      expect(engine.searchAll('Ahmed'), contains('INV-001'));
      expect(engine.searchAll('invoice'), hasLength(2));
    });

    // ── getStats ──────────────────────────────────────────────────────────

    test('getStats: reflects current state', () {
      engine.indexEntry('A', 'foo bar baz');
      engine.indexEntry('B', 'foo qux');
      final stats = engine.getStats();
      expect(stats.totalEntries, equals(2));
      expect(stats.totalKeywords, greaterThanOrEqualTo(4));
      expect(stats.memoryEstimateBytes, greaterThan(0));
    });

    test('getStats: empty index returns IndexStats.empty()', () {
      final stats = engine.getStats();
      expect(stats.totalEntries, equals(0));
      expect(stats.totalKeywords, equals(0));
    });

    // ── Performance ───────────────────────────────────────────────────────

    test('performance: search 10,000 entries in < 5ms', () {
      for (int i = 0; i < 10000; i++) {
        engine.indexEntry('KEY-$i', 'Invoice $i client Ahmed amount ${i * 100}');
      }
      final sw = Stopwatch()..start();
      final results = engine.searchAll('ahmed invoice');
      sw.stop();
      expect(results.length, greaterThan(0));
      expect(
        sw.elapsedMilliseconds,
        lessThan(5),
        reason: 'O(1) index search should be fast even for 10k entries',
      );
    });
  });
}
