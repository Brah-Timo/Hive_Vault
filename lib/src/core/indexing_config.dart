// lib/src/core/indexing_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Indexing engine configuration.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';

/// Immutable configuration for the in-memory indexing engine.
@immutable
class IndexingConfig {
  /// When `true` the index is updated automatically on every save/delete.
  final bool enableAutoIndexing;

  /// Tokens (words) shorter than this number of characters are ignored.
  /// Filters out noise words like "a", "in", "or".
  final int minimumTokenLength;

  /// Maximum number of tokens stored per indexed entry.
  /// Caps memory usage for entries with very long searchable text.
  final int maxTokensPerEntry;

  /// When `true` enables prefix-based search (starts-with queries).
  /// Slightly increases index traversal cost but enables autocomplete.
  final bool enablePrefixSearch;

  /// When `true` the initial index rebuild runs in a background isolate
  /// instead of on the main thread. Recommended for large datasets.
  final bool buildIndexInBackground;

  /// If non-empty, only these JSON field names are included in the
  /// searchable text extracted from Map objects.
  /// An empty list means all String-valued fields are indexed.
  final List<String> indexableFields;

  /// Set of common stop-words to exclude from the index.
  /// Reduces index size and improves search precision.
  final Set<String> stopWords;

  const IndexingConfig({
    this.enableAutoIndexing = true,
    this.minimumTokenLength = 2,
    this.maxTokensPerEntry = 100,
    this.enablePrefixSearch = true,
    this.buildIndexInBackground = true,
    this.indexableFields = const [],
    this.stopWords = const {
      'the',
      'a',
      'an',
      'and',
      'or',
      'of',
      'in',
      'on',
      'at',
      'to',
      'for',
      'is',
      'it',
      'its',
      'this',
      'that',
      'with',
      'by',
      'from',
    },
  }) : assert(
          minimumTokenLength >= 1,
          'minimumTokenLength must be at least 1',
        );

  // ─── Predefined presets ──────────────────────────────────────────────────

  /// Full indexing with prefix search — best for large ERP datasets.
  const IndexingConfig.full()
      : this(
          enableAutoIndexing: true,
          enablePrefixSearch: true,
          buildIndexInBackground: true,
        );

  /// Indexing disabled — useful for write-heavy append-only scenarios.
  const IndexingConfig.disabled()
      : this(
          enableAutoIndexing: false,
          enablePrefixSearch: false,
          buildIndexInBackground: false,
        );

  /// Lightweight indexing — no prefix search, smaller token budget.
  const IndexingConfig.light()
      : this(
          enableAutoIndexing: true,
          minimumTokenLength: 3,
          maxTokensPerEntry: 30,
          enablePrefixSearch: false,
          buildIndexInBackground: false,
        );

  // ─── Equality & copy ─────────────────────────────────────────────────────

  IndexingConfig copyWith({
    bool? enableAutoIndexing,
    int? minimumTokenLength,
    int? maxTokensPerEntry,
    bool? enablePrefixSearch,
    bool? buildIndexInBackground,
    List<String>? indexableFields,
    Set<String>? stopWords,
  }) {
    return IndexingConfig(
      enableAutoIndexing: enableAutoIndexing ?? this.enableAutoIndexing,
      minimumTokenLength: minimumTokenLength ?? this.minimumTokenLength,
      maxTokensPerEntry: maxTokensPerEntry ?? this.maxTokensPerEntry,
      enablePrefixSearch: enablePrefixSearch ?? this.enablePrefixSearch,
      buildIndexInBackground:
          buildIndexInBackground ?? this.buildIndexInBackground,
      indexableFields: indexableFields ?? this.indexableFields,
      stopWords: stopWords ?? this.stopWords,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexingConfig &&
          enableAutoIndexing == other.enableAutoIndexing &&
          minimumTokenLength == other.minimumTokenLength &&
          maxTokensPerEntry == other.maxTokensPerEntry &&
          enablePrefixSearch == other.enablePrefixSearch &&
          buildIndexInBackground == other.buildIndexInBackground;

  @override
  int get hashCode => Object.hash(
        enableAutoIndexing,
        minimumTokenLength,
        maxTokensPerEntry,
        enablePrefixSearch,
        buildIndexInBackground,
      );

  @override
  String toString() => 'IndexingConfig('
      'autoIndex: $enableAutoIndexing, '
      'minToken: $minimumTokenLength, '
      'prefix: $enablePrefixSearch)';
}
