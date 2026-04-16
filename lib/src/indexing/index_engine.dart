// lib/src/indexing/index_engine.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — In-memory inverted index engine.
// Provides O(1) token lookup, AND/OR/Prefix search, and atomic updates.
// ─────────────────────────────────────────────────────────────────────────────

import '../core/indexing_config.dart';
import '../core/vault_stats.dart';
import 'tokenizer.dart';

/// In-memory inverted index for fast full-text search over vault keys.
///
/// ## Data structures
/// - `_invertedIndex`:  token → Set<key>   (lookup: which keys contain token)
/// - `_reverseIndex`:   key   → Set<token> (used for updates and deletes)
///
/// ## Thread-safety
/// This class is NOT thread-safe. In Flutter all Hive calls happen on the
/// main isolate so no additional synchronisation is needed. If you run
/// HiveVault in a background isolate, protect access with a Mutex.
///
/// ## Complexity
/// - `indexEntry`: O(t) where t = number of tokens.
/// - `searchAll` / `searchAny`: O(t) where t = number of query tokens.
/// - `removeEntry`: O(t) amortised.
/// - `searchPrefix`: O(k) where k = total unique keywords.
class InMemoryIndexEngine {
  final IndexingConfig config;
  final Tokenizer _tokenizer;

  /// inverted index: token → {key1, key2, …}
  final Map<String, Set<String>> _invertedIndex = {};

  /// reverse index: key → {token1, token2, …}
  final Map<String, Set<String>> _reverseIndex = {};

  InMemoryIndexEngine(this.config) : _tokenizer = Tokenizer(config);

  // ─── Statistics ───────────────────────────────────────────────────────────

  /// Total number of indexed entries.
  int get indexedCount => _reverseIndex.length;

  /// Total unique tokens in the index.
  int get keywordCount => _invertedIndex.length;

  bool get isEmpty => _reverseIndex.isEmpty;

  // ═══════════════════════════════════════════════════════════════════════════
  //  Mutating operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adds (or updates) an entry in the index.
  ///
  /// If [key] already has index entries they are replaced atomically.
  /// [searchableText] is tokenised by the configured [Tokenizer].
  void indexEntry(String key, String searchableText) {
    // Remove stale tokens for this key first.
    _removeTokensForKey(key);

    final tokens = _tokenizer.tokenize(searchableText);
    if (tokens.isEmpty) return;

    // Store forward mapping (key → tokens).
    _reverseIndex[key] = tokens;

    // Update inverted index (token → keys).
    for (final token in tokens) {
      (_invertedIndex[token] ??= <String>{}).add(key);
    }
  }

  /// Removes all index entries for [key].
  void removeEntry(String key) {
    _removeTokensForKey(key);
  }

  /// Removes all entries and resets the index to an empty state.
  void clearIndex() {
    _invertedIndex.clear();
    _reverseIndex.clear();
  }

  /// Rebuilds the index from a map of key → searchableText pairs.
  ///
  /// The existing index is cleared before rebuilding. Thread-safety is the
  /// caller's responsibility.
  void rebuildFrom(Map<String, String> corpus) {
    clearIndex();
    for (final entry in corpus.entries) {
      indexEntry(entry.key, entry.value);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Search operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the set of keys whose index entries contain ALL tokens in [query].
  ///
  /// Returns an empty set if [query] is empty or no matches exist.
  /// Complexity: O(t · log m) where t = query token count, m = match set size.
  Set<String> searchAll(String query) {
    final tokens = _tokenizer.tokenizeQuery(query);
    if (tokens.isEmpty) return const {};

    Set<String>? result;
    for (final token in tokens) {
      final matches = _invertedIndex[token];
      if (matches == null || matches.isEmpty) return const {};
      result = result == null
          ? Set<String>.of(matches)
          : result.intersection(matches);
      if (result.isEmpty) return const {};
    }

    return result ?? const {};
  }

  /// Returns the set of keys whose index entries contain ANY token in [query].
  Set<String> searchAny(String query) {
    final tokens = _tokenizer.tokenizeQuery(query);
    if (tokens.isEmpty) return const {};

    final result = <String>{};
    for (final token in tokens) {
      final matches = _invertedIndex[token];
      if (matches != null) result.addAll(matches);
    }
    return result;
  }

  /// Returns keys that have at least one token starting with [prefix].
  ///
  /// Complexity: O(k) where k = total unique keywords. For large indexes
  /// consider using a trie data structure instead.
  Set<String> searchPrefix(String prefix) {
    if (prefix.isEmpty) return const {};
    final normPrefix = _tokenizer.normaliseQuery(prefix);
    if (normPrefix.length < config.minimumTokenLength) return const {};

    final result = <String>{};
    for (final entry in _invertedIndex.entries) {
      if (entry.key.startsWith(normPrefix)) {
        result.addAll(entry.value);
      }
    }
    return result;
  }

  /// Returns all keys currently in the index.
  Set<String> allKeys() => Set.unmodifiable(_reverseIndex.keys);

  /// Returns `true` if [key] is indexed.
  bool isIndexed(String key) => _reverseIndex.containsKey(key);

  // ═══════════════════════════════════════════════════════════════════════════
  //  Diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Computes and returns current index statistics.
  IndexStats getStats() {
    if (_reverseIndex.isEmpty) return const IndexStats.empty();

    final totalTokens =
        _reverseIndex.values.fold<int>(0, (sum, s) => sum + s.length);
    final average = totalTokens / _reverseIndex.length;
    final memory = _estimateMemoryBytes();

    return IndexStats(
      totalEntries: _reverseIndex.length,
      totalKeywords: _invertedIndex.length,
      averageKeywordsPerEntry: average,
      memoryEstimateBytes: memory,
    );
  }

  /// Pretty-prints the index for debugging. Limited to [maxEntries] tokens.
  String debugDump({int maxEntries = 20}) {
    final buf = StringBuffer('InMemoryIndex [\n');
    int count = 0;
    for (final entry in _invertedIndex.entries) {
      if (count++ >= maxEntries) {
        buf.writeln('  ... (${_invertedIndex.length - maxEntries} more)');
        break;
      }
      buf.writeln('  "${entry.key}" → ${entry.value}');
    }
    buf.write(']');
    return buf.toString();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  void _removeTokensForKey(String key) {
    final tokens = _reverseIndex.remove(key);
    if (tokens == null) return;
    for (final token in tokens) {
      final keySet = _invertedIndex[token];
      if (keySet == null) continue;
      keySet.remove(key);
      if (keySet.isEmpty) _invertedIndex.remove(token);
    }
  }

  int _estimateMemoryBytes() {
    // Each token string ~ 2 bytes per char (UTF-16).
    // Each key reference in a Set<String> ~ 32 bytes (pointer + String header).
    int bytes = 0;
    for (final entry in _invertedIndex.entries) {
      bytes += entry.key.length * 2; // token storage
      bytes += entry.value.length * 32; // key references
    }
    // Reverse index: key strings + Set overhead.
    for (final entry in _reverseIndex.entries) {
      bytes += entry.key.length * 2;
      bytes += entry.value.length * 20;
    }
    return bytes;
  }
}
