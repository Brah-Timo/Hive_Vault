// lib/src/sync/vault_synchronizer.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Vault Synchronizer.
//
// Provides bidirectional synchronisation between a local HiveVault and a
// remote data source (another vault, REST endpoint, S3-compatible store, …).
//
// Sync protocol:
//   1. PULL  — download remote snapshot (via RemoteDataSource).
//   2. DIFF  — compare remote entries with local; detect new/updated/deleted.
//   3. MERGE — resolve conflicts using the configured ConflictResolver.
//   4. PUSH  — upload locally-modified entries to the remote.
//   5. COMMIT— persist sync metadata (last-sync cursor, sync log).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import '../core/vault_interface.dart';
import '../core/vault_exceptions.dart';
import 'conflict_resolver.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Remote data source abstraction
// ═══════════════════════════════════════════════════════════════════════════

/// Abstract interface for the remote data source used during sync.
///
/// Implement this to connect to REST, Firebase, S3, gRPC, etc.
abstract class RemoteDataSource {
  /// Fetches all remote entries modified since [cursor] (epoch ms, or 0 for
  /// full sync).  Returns a map of key → serialized JSON string.
  Future<Map<String, String>> fetchSince(int cursor);

  /// Pushes [entries] (key → JSON value) to the remote.
  Future<void> push(Map<String, String> entries);

  /// Deletes [keys] from the remote.
  Future<void> deleteKeys(List<String> keys);

  /// Returns the current remote cursor (epoch ms of latest change).
  Future<int> getRemoteCursor();
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sync configuration
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for the synchronizer.
class SyncConfig {
  /// Whether to enable periodic background sync.
  final bool enablePeriodicSync;

  /// Interval between periodic syncs (ignored if [enablePeriodicSync] is false).
  final Duration syncInterval;

  /// Maximum number of conflict resolution retries per key.
  final int maxConflictRetries;

  /// Whether to push local deletes to the remote.
  final bool syncDeletes;

  /// Maximum number of entries to push/pull per sync batch.
  final int batchSize;

  const SyncConfig({
    this.enablePeriodicSync = false,
    this.syncInterval = const Duration(minutes: 15),
    this.maxConflictRetries = 3,
    this.syncDeletes = true,
    this.batchSize = 500,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sync result
// ═══════════════════════════════════════════════════════════════════════════

/// Outcome of a single sync run.
class SyncResult {
  final DateTime startedAt;
  final DateTime completedAt;
  final int pulled;
  final int pushed;
  final int conflicts;
  final int resolved;
  final int errors;
  final List<String> errorDetails;
  final int newCursor;
  final bool success;

  const SyncResult({
    required this.startedAt,
    required this.completedAt,
    required this.pulled,
    required this.pushed,
    required this.conflicts,
    required this.resolved,
    required this.errors,
    required this.errorDetails,
    required this.newCursor,
    required this.success,
  });

  Duration get elapsed => completedAt.difference(startedAt);

  @override
  String toString() =>
      'SyncResult(pulled: $pulled, pushed: $pushed, conflicts: $conflicts, '
      'resolved: $resolved, errors: $errors, elapsed: ${elapsed.inMilliseconds}ms, '
      'success: $success)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sync event stream types
// ═══════════════════════════════════════════════════════════════════════════

enum SyncEventType { started, progress, conflictDetected, completed, failed }

class SyncEvent {
  final SyncEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  SyncEvent({
    required this.type,
    required this.message,
    this.data = const {},
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'SyncEvent(${type.name}: $message)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Vault Synchronizer
// ═══════════════════════════════════════════════════════════════════════════

/// Synchronises a local [SecureStorageInterface] with a [RemoteDataSource].
///
/// ```dart
/// final sync = VaultSynchronizer(
///   local: myVault,
///   remote: MyRestRemote(),
///   resolver: LastWriteWinsResolver(),
///   config: SyncConfig(enablePeriodicSync: true),
/// );
/// await sync.initialize();
/// sync.startPeriodicSync();
/// final result = await sync.syncNow();
/// ```
class VaultSynchronizer<T> {
  final SecureStorageInterface _local;
  final RemoteDataSource _remote;
  final ConflictResolver<T> _resolver;
  final SyncConfig config;

  Timer? _syncTimer;
  bool _syncing = false;
  int _lastSyncCursor = 0;

  // Persistence.
  static const _metaBoxName = '__sync_meta__';
  static const _cursorKey = 'last_sync_cursor';
  Box<String>? _metaBox;

  // Streams.
  final StreamController<SyncEvent> _eventStream =
      StreamController.broadcast();
  final StreamController<SyncResult> _resultStream =
      StreamController.broadcast();

  Stream<SyncEvent> get events => _eventStream.stream;
  Stream<SyncResult> get results => _resultStream.stream;

  VaultSynchronizer({
    required SecureStorageInterface local,
    required RemoteDataSource remote,
    required ConflictResolver<T> resolver,
    this.config = const SyncConfig(),
  })  : _local = local,
        _remote = remote,
        _resolver = resolver;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _metaBox = await Hive.openBox<String>(_metaBoxName);
    final saved = _metaBox!.get(_cursorKey);
    if (saved != null) _lastSyncCursor = int.tryParse(saved) ?? 0;
  }

  void startPeriodicSync() {
    if (!config.enablePeriodicSync) return;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(config.syncInterval, (_) => syncNow());
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> dispose() async {
    stopPeriodicSync();
    await _eventStream.close();
    await _resultStream.close();
    await _metaBox?.close();
  }

  // ── Sync execution ────────────────────────────────────────────────────────

  /// Runs a full sync cycle.  Returns a [SyncResult] summarising the run.
  Future<SyncResult> syncNow() async {
    if (_syncing) {
      return SyncResult(
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
        pulled: 0,
        pushed: 0,
        conflicts: 0,
        resolved: 0,
        errors: 1,
        errorDetails: ['Sync already in progress'],
        newCursor: _lastSyncCursor,
        success: false,
      );
    }

    _syncing = true;
    final startedAt = DateTime.now();
    int pulled = 0, pushed = 0, conflicts = 0, resolved = 0, errors = 0;
    final errorDetails = <String>[];

    _emit(SyncEventType.started, 'Sync started (cursor: $_lastSyncCursor)');

    try {
      // ── PULL ──────────────────────────────────────────────────────────────
      final remoteEntries = await _remote.fetchSince(_lastSyncCursor);
      _emit(SyncEventType.progress,
          'Pulled ${remoteEntries.length} entries from remote');

      for (final entry in remoteEntries.entries) {
        try {
          final remoteValue = jsonDecode(entry.value);
          final localValue = await _local.secureGet<dynamic>(entry.key);

          if (localValue == null) {
            // New remote entry → save locally.
            await _local.secureSave(entry.key, remoteValue);
            pulled++;
          } else if (remoteValue != localValue) {
            // Potential conflict.
            conflicts++;
            final localVV = VersionedValue<T>(
              value: localValue as T,
              sourceId: 'local',
              timestamp: DateTime.now(),
              version: 1,
            );
            final remoteVV = VersionedValue<T>(
              value: remoteValue as T,
              sourceId: 'remote',
              timestamp: DateTime.now(),
              version: 2,
            );
            final conflict = VaultConflict<T>(
              key: entry.key,
              local: localVV,
              remote: remoteVV,
            );
            _emit(SyncEventType.conflictDetected,
                'Conflict on key: ${entry.key}');

            final resolution = await _resolver.resolve(conflict);
            await _local.secureSave(entry.key, resolution.resolvedValue);
            resolved++;
          }
        } catch (e) {
          errors++;
          errorDetails.add('PULL ${entry.key}: $e');
        }
      }

      // ── PUSH ──────────────────────────────────────────────────────────────
      if (_lastSyncCursor > 0) {
        final localKeys = await _local.getAllKeys();
        final toPush = <String, String>{};

        for (final key in localKeys) {
          try {
            final value = await _local.secureGet<dynamic>(key);
            if (value != null) {
              toPush[key] = jsonEncode(value);
            }
          } catch (e) {
            errors++;
            errorDetails.add('PUSH serialize $key: $e');
          }
        }

        // Push in batches.
        final batches = _splitBatches(toPush, config.batchSize);
        for (final batch in batches) {
          try {
            await _remote.push(batch);
            pushed += batch.length;
          } catch (e) {
            errors++;
            errorDetails.add('PUSH batch: $e');
          }
        }
      }

      // ── UPDATE CURSOR ─────────────────────────────────────────────────────
      final newCursor = await _remote.getRemoteCursor();
      _lastSyncCursor = newCursor;
      await _metaBox?.put(_cursorKey, newCursor.toString());

      final result = SyncResult(
        startedAt: startedAt,
        completedAt: DateTime.now(),
        pulled: pulled,
        pushed: pushed,
        conflicts: conflicts,
        resolved: resolved,
        errors: errors,
        errorDetails: errorDetails,
        newCursor: newCursor,
        success: errors == 0,
      );

      _emit(SyncEventType.completed,
          'Sync completed: pulled=$pulled pushed=$pushed conflicts=$conflicts');
      _resultStream.add(result);
      return result;
    } catch (e) {
      _emit(SyncEventType.failed, 'Sync failed: $e');
      throw VaultStorageException('Sync failed', cause: e);
    } finally {
      _syncing = false;
    }
  }

  // ── Status ────────────────────────────────────────────────────────────────

  bool get isSyncing => _syncing;
  int get lastSyncCursor => _lastSyncCursor;

  // ── Private ───────────────────────────────────────────────────────────────

  void _emit(SyncEventType type, String message,
      [Map<String, dynamic>? data]) {
    _eventStream.add(SyncEvent(
      type: type,
      message: message,
      data: data ?? {},
    ));
  }

  List<Map<String, String>> _splitBatches(
      Map<String, String> all, int size) {
    final batches = <Map<String, String>>[];
    final keys = all.keys.toList();
    for (int i = 0; i < keys.length; i += size) {
      final batchKeys = keys.skip(i).take(size);
      batches.add({for (final k in batchKeys) k: all[k]!});
    }
    return batches;
  }
}
