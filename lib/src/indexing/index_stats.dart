// lib/src/indexing/index_stats.dart

import 'package:meta/meta.dart';

/// Snapshot of the in-memory inverted index at a given point in time.
@immutable
class IndexStats {
  const IndexStats({
    required this.totalEntries,
    required this.totalKeywords,
    required this.averageKeywordsPerEntry,
    required this.memoryEstimateBytes,
  });

  /// Number of vault entries currently represented in the index.
  final int totalEntries;

  /// Total distinct tokens stored across all indexed entries.
  final int totalKeywords;

  /// Mean number of tokens per indexed entry.
  final double averageKeywordsPerEntry;

  /// Rough estimate of RAM consumed by the index (bytes).
  final int memoryEstimateBytes;

  @override
  String toString() {
    final kb = (memoryEstimateBytes / 1024).toStringAsFixed(1);
    final avg = averageKeywordsPerEntry.toStringAsFixed(1);
    return 'IndexStats('
        'entries=$totalEntries, '
        'keywords=$totalKeywords, '
        'avg=$avg tokens/entry, '
        'memory=${kb}KB)';
  }
}
