// lib/src/background/vault_counters.dart
//
// HiveVault — Mutable runtime counters used to populate [VaultStats].

/// Holds mutable runtime counters for a single [HiveVaultImpl] instance.
///
/// All fields are incremented directly (no atomic ops needed — Flutter is
/// single-threaded on the UI Isolate).
class VaultCounters {
  int cacheHits = 0;
  int cacheMisses = 0;
  int totalSaveOps = 0;
  int totalReadOps = 0;
  int totalDeleteOps = 0;
  int totalBytesWritten = 0;
  int totalBytesAfterCompression = 0;

  void reset() {
    cacheHits = 0;
    cacheMisses = 0;
    totalSaveOps = 0;
    totalReadOps = 0;
    totalDeleteOps = 0;
    totalBytesWritten = 0;
    totalBytesAfterCompression = 0;
  }

  @override
  String toString() =>
      'VaultCounters(saves=$totalSaveOps, reads=$totalReadOps, '
      'deletes=$totalDeleteOps, cacheHits=$cacheHits, '
      'bytesWritten=$totalBytesWritten, '
      'bytesStored=$totalBytesAfterCompression)';
}
