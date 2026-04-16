// lib/src/indexing/indexing_config.dart

import 'package:meta/meta.dart';

/// Indexing settings carried inside [VaultConfig].
@immutable
class IndexingConfig {
  const IndexingConfig({
    this.enableAutoIndexing = true,
    this.minimumTokenLength = 2,
    this.maxTokensPerEntry = 100,
    this.enablePrefixSearch = true,
    this.buildIndexInBackground = true,
    this.indexableFields = const [],
  });

  /// When `true`, the index is automatically updated on every [secureSave]
  /// and [secureDelete].
  final bool enableAutoIndexing;

  /// Tokens shorter than this value are discarded during tokenisation.
  final int minimumTokenLength;

  /// Maximum tokens extracted per entry. Excess tokens are silently dropped.
  /// Prevents the index from growing unbounded for very large text blobs.
  final int maxTokensPerEntry;

  /// When `true`, [secureSearchPrefix] performs a linear scan of all index
  /// keys looking for matching prefixes.
  ///
  /// Disable if prefix search is never used and the index is very large.
  final bool enablePrefixSearch;

  /// When `true`, the initial full-index rebuild at vault open time is
  /// performed inside a Dart Isolate so the UI thread is not blocked.
  final bool buildIndexInBackground;

  /// If non-empty, only these map keys are included in the searchable text
  /// extracted from stored objects during index rebuild.
  ///
  /// An empty list means "use all String-valued fields".
  final List<String> indexableFields;

  @override
  String toString() => 'IndexingConfig(autoIndex=$enableAutoIndexing, '
      'minTokenLen=$minimumTokenLength, prefix=$enablePrefixSearch)';
}
