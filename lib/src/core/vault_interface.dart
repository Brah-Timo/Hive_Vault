// lib/src/core/vault_interface.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — The main public abstract interface.
// All business logic depends on this contract, never on the concrete impl.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'sensitivity_level.dart';
import 'vault_stats.dart';
import '../audit/audit_entry.dart';

/// The primary contract for a secure storage vault.
///
/// Each method is documented with its expected behaviour, error surface, and
/// performance characteristics so that both implementors and callers have a
/// clear shared understanding.
abstract class SecureStorageInterface {
  // ═══════════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialises the vault (opens the underlying Hive box, derives keys,
  /// builds the in-memory index). Must be called before any other method.
  ///
  /// Throws [VaultInitException] if the underlying store cannot be opened.
  Future<void> initialize();

  /// Releases all resources: closes the Hive box, clears the index, purges
  /// the cache, and flushes any pending audit entries to disk.
  Future<void> close();

  // ═══════════════════════════════════════════════════════════════════════════
  //  Core CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Persists [value] under [key] with optional compression, encryption, and
  /// index registration.
  ///
  /// Parameters:
  /// - [key]             Unique storage key (must not be null or empty).
  /// - [value]           Any Dart object that is JSON-serialisable, or a
  ///                     [Uint8List] for raw binary data.
  /// - [sensitivity]     Overrides the default sensitivity from [VaultConfig].
  /// - [searchableText]  Text that will be tokenised and added to the index.
  ///                     If `null` and [value] is a [Map], field values are
  ///                     extracted automatically when auto-indexing is on.
  ///
  /// Throws [VaultEncryptionException] or [VaultCompressionException] on
  /// pipeline failures.
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  });

  /// Retrieves the entry stored under [key], decrypts and decompresses it,
  /// and returns it as [T].
  ///
  /// Returns `null` if the key does not exist.
  ///
  /// Throws [VaultDecryptionException] if the payload cannot be decrypted.
  /// Throws [VaultIntegrityException] if GCM authentication fails.
  Future<T?> secureGet<T>(String key);

  /// Removes the entry at [key] from storage and clears it from the index
  /// and cache.
  Future<void> secureDelete(String key);

  /// Returns `true` if an entry with [key] exists in the vault.
  Future<bool> secureContains(String key);

  /// Returns all keys currently stored in the vault.
  Future<List<String>> getAllKeys();

  // ═══════════════════════════════════════════════════════════════════════════
  //  Batch Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// Atomically (best-effort) saves all [entries] in a single batch.
  ///
  /// Each entry is processed individually through the full pipeline.
  /// On failure the successfully saved entries are NOT rolled back.
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  });

  /// Retrieves multiple entries in parallel and returns a map of
  /// key → decrypted value. Missing keys are omitted from the result.
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys);

  /// Deletes all [keys] and cleans up their index and cache entries.
  Future<void> secureDeleteBatch(List<String> keys);

  // ═══════════════════════════════════════════════════════════════════════════
  //  Search
  // ═══════════════════════════════════════════════════════════════════════════

  /// Full-text AND search: returns entries whose index contains ALL tokens in
  /// [query]. Uses the in-memory inverted index for O(1) token lookups.
  Future<List<T>> secureSearch<T>(String query);

  /// Full-text OR search: returns entries whose index contains ANY token in
  /// [query].
  Future<List<T>> secureSearchAny<T>(String query);

  /// Prefix search: returns entries that have at least one indexed token
  /// starting with [prefix].
  Future<List<T>> secureSearchPrefix<T>(String prefix);

  /// Returns the storage keys (not values) matching an AND search.
  Future<Set<String>> searchKeys(String query);

  // ═══════════════════════════════════════════════════════════════════════════
  //  Maintenance
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scans all stored entries and rebuilds the in-memory index from scratch.
  /// Useful after bulk imports or recovery from index corruption.
  Future<void> rebuildIndex();

  /// Triggers Hive's internal compaction to reclaim space from deleted entries.
  Future<void> compact();

  /// Clears the LRU memory cache.
  void clearCache();

  // ═══════════════════════════════════════════════════════════════════════════
  //  Import / Export
  // ═══════════════════════════════════════════════════════════════════════════

  /// Exports all entries as an encrypted binary archive (AES-256-GCM + JSON).
  /// The archive is self-contained and can be imported into another vault.
  Future<Uint8List> exportEncrypted();

  /// Imports an encrypted archive produced by [exportEncrypted].
  /// Existing entries with the same key are overwritten.
  Future<void> importEncrypted(Uint8List data);

  // ═══════════════════════════════════════════════════════════════════════════
  //  Diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns current runtime statistics.
  Future<VaultStats> getStats();

  /// Returns recent audit log entries (newest first).
  List<AuditEntry> getAuditLog({int limit = 50});
}
