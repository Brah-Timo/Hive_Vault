// lib/src/impl/vault_stats_counter.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Mutable runtime statistics accumulator.
// Consumed by HiveVaultImpl to build VaultStats snapshots.
// ─────────────────────────────────────────────────────────────────────────────

/// Accumulates mutable counters and byte totals tracked during vault operation.
/// This class is internal — callers receive immutable [VaultStats] snapshots.
class VaultStatsCounter {
  DateTime openedAt = DateTime.now();

  int totalWrites = 0;
  int totalReads = 0;
  int totalSearches = 0;

  /// Total original (pre-compression) bytes written.
  int totalOriginalBytesWritten = 0;

  /// Total bytes written to the Hive box (after compression + encryption).
  int totalBytesWritten = 0;

  /// Total bytes saved by compression (originalSize - compressedSize).
  int totalBytesSaved = 0;

  // ─── Update helpers ───────────────────────────────────────────────────────

  void recordWrite({
    required int originalSize,
    required int finalSize,
  }) {
    totalWrites++;
    totalOriginalBytesWritten += originalSize;
    totalBytesWritten += finalSize;
    final saved = originalSize - finalSize;
    if (saved > 0) totalBytesSaved += saved;
  }

  void recordRead() => totalReads++;

  void recordSearch() => totalSearches++;

  void reset() {
    openedAt = DateTime.now();
    totalWrites = 0;
    totalReads = 0;
    totalSearches = 0;
    totalOriginalBytesWritten = 0;
    totalBytesWritten = 0;
    totalBytesSaved = 0;
  }
}
