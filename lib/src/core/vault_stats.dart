// lib/src/core/vault_stats.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Runtime statistics and index diagnostics.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';

/// Statistics for the in-memory index.
@immutable
class IndexStats {
  /// Total number of entries currently in the index.
  final int totalEntries;

  /// Total number of unique keyword tokens stored in the inverted index.
  final int totalKeywords;

  /// Average number of keyword tokens per indexed entry.
  final double averageKeywordsPerEntry;

  /// Estimated heap memory used by the index (bytes).
  final int memoryEstimateBytes;

  const IndexStats({
    required this.totalEntries,
    required this.totalKeywords,
    required this.averageKeywordsPerEntry,
    required this.memoryEstimateBytes,
  });

  /// Empty / zero stats (for when indexing is disabled).
  const IndexStats.empty()
      : totalEntries = 0,
        totalKeywords = 0,
        averageKeywordsPerEntry = 0,
        memoryEstimateBytes = 0;

  String get memoryLabel {
    if (memoryEstimateBytes < 1024) return '$memoryEstimateBytes B';
    if (memoryEstimateBytes < 1048576) {
      return '${(memoryEstimateBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(memoryEstimateBytes / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  String toString() => 'IndexStats('
      'entries: $totalEntries, '
      'keywords: $totalKeywords, '
      'avg: ${averageKeywordsPerEntry.toStringAsFixed(1)}, '
      'memory: $memoryLabel)';
}

// ─────────────────────────────────────────────────────────────────────────────

/// Comprehensive runtime statistics for a [HiveVault] instance.
@immutable
class VaultStats {
  /// Name of the underlying Hive box.
  final String boxName;

  /// Total number of entries stored in the box.
  final int totalEntries;

  /// Current size of the LRU memory cache.
  final int cacheSize;

  /// Maximum capacity of the LRU cache.
  final int cacheCapacity;

  /// Hit ratio of the LRU cache (0.0 – 1.0).
  final double cacheHitRatio;

  /// Compression algorithm in use.
  final String compressionAlgorithm;

  /// Encryption algorithm in use.
  final String encryptionAlgorithm;

  /// Index statistics.
  final IndexStats indexStats;

  /// Total bytes saved by compression since the vault was opened.
  final int totalBytesSaved;

  /// Total bytes written to the underlying store since the vault was opened.
  final int totalBytesWritten;

  /// Total number of write operations since the vault was opened.
  final int totalWrites;

  /// Total number of read operations since the vault was opened.
  final int totalReads;

  /// Total number of search operations since the vault was opened.
  final int totalSearches;

  /// Timestamp when the vault was opened.
  final DateTime openedAt;

  const VaultStats({
    required this.boxName,
    required this.totalEntries,
    required this.cacheSize,
    required this.cacheCapacity,
    required this.cacheHitRatio,
    required this.compressionAlgorithm,
    required this.encryptionAlgorithm,
    required this.indexStats,
    required this.totalBytesSaved,
    required this.totalBytesWritten,
    required this.totalWrites,
    required this.totalReads,
    required this.totalSearches,
    required this.openedAt,
  });

  /// Overall compression ratio (0.0 – 1.0).
  double get compressionRatio {
    final original = totalBytesWritten + totalBytesSaved;
    if (original == 0) return 0.0;
    return totalBytesSaved / original;
  }

  String get compressionRatioLabel =>
      '${(compressionRatio * 100).toStringAsFixed(1)}%';

  Duration get uptime => DateTime.now().difference(openedAt);

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('╔══════════════════════════════════════════════╗')
      ..writeln('║          HiveVault Statistics                ║')
      ..writeln('╠══════════════════════════════════════════════╣')
      ..writeln('║  Box        : $boxName')
      ..writeln('║  Entries    : $totalEntries')
      ..writeln('║  Uptime     : ${uptime.inSeconds}s')
      ..writeln('║  Compression: $compressionAlgorithm '
          '($compressionRatioLabel saved)')
      ..writeln('║  Encryption : $encryptionAlgorithm')
      ..writeln('║  Cache      : $cacheSize/$cacheCapacity '
          '(hit: ${(cacheHitRatio * 100).toStringAsFixed(1)}%)')
      ..writeln('║  Writes     : $totalWrites '
          '(${(totalBytesWritten / 1024).toStringAsFixed(1)} KB)')
      ..writeln('║  Reads      : $totalReads')
      ..writeln('║  Searches   : $totalSearches')
      ..writeln('║  Index      : $indexStats')
      ..writeln('╚══════════════════════════════════════════════╝');
    return buf.toString();
  }
}
