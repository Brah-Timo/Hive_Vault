// lib/src/impl/reactive_vault.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Reactive wrapper that exposes vault changes as Dart Streams.
// ─────────────────────────────────────────────────────────────────────────────
//
// Allows Flutter widgets to listen for data changes and rebuild automatically.
//
// Usage with StreamBuilder:
//   ```dart
//   StreamBuilder<VaultEvent>(
//     stream: reactiveVault.watch('INV-001'),
//     builder: (ctx, snap) { … },
//   )
//   ```
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';
import '../audit/audit_entry.dart';
import '../core/vault_interface.dart';
import '../core/sensitivity_level.dart';
import '../core/vault_stats.dart';

/// Describes the kind of change that occurred.
enum VaultEventType { saved, deleted, batchSaved, batchDeleted, cleared }

/// An event emitted by [ReactiveVault] when vault data changes.
class VaultEvent {
  /// The key that changed (or a description for batch operations).
  final String key;

  /// The type of change.
  final VaultEventType type;

  /// Timestamp of the event.
  final DateTime timestamp;

  const VaultEvent({
    required this.key,
    required this.type,
    required this.timestamp,
  });

  @override
  String toString() => 'VaultEvent(${type.name}, key: "$key", '
      'at: ${timestamp.toIso8601String()})';
}

/// A decorator around [SecureStorageInterface] that emits [VaultEvent]s on
/// every mutation (save, delete, batch).
///
/// Callers subscribe via [watchAll], [watch], or [watchKeys].
class ReactiveVault implements SecureStorageInterface {
  final SecureStorageInterface _inner;
  final _controller = StreamController<VaultEvent>.broadcast();

  ReactiveVault(this._inner);

  // ─── Stream access ────────────────────────────────────────────────────────

  /// Stream of ALL vault change events.
  Stream<VaultEvent> get watchAll => _controller.stream;

  /// Stream of change events for a specific [key].
  Stream<VaultEvent> watch(String key) =>
      _controller.stream.where((e) => e.key == key);

  /// Stream of change events for any key in [keys].
  Stream<VaultEvent> watchKeys(Set<String> keys) =>
      _controller.stream.where((e) => keys.contains(e.key));

  // ─── Emit helpers ─────────────────────────────────────────────────────────

  void _emit(String key, VaultEventType type) {
    if (!_controller.isClosed) {
      _controller.add(VaultEvent(
        key: key,
        type: type,
        timestamp: DateTime.now(),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Delegating implementations
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> close() async {
    await _controller.close();
    await _inner.close();
  }

  @override
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  }) async {
    await _inner.secureSave(key, value,
        sensitivity: sensitivity, searchableText: searchableText);
    _emit(key, VaultEventType.saved);
  }

  @override
  Future<T?> secureGet<T>(String key) => _inner.secureGet<T>(key);

  @override
  Future<void> secureDelete(String key) async {
    await _inner.secureDelete(key);
    _emit(key, VaultEventType.deleted);
  }

  @override
  Future<bool> secureContains(String key) => _inner.secureContains(key);

  @override
  Future<List<String>> getAllKeys() => _inner.getAllKeys();

  @override
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  }) async {
    await _inner.secureSaveBatch(entries, sensitivity: sensitivity);
    for (final key in entries.keys) {
      _emit(key, VaultEventType.saved);
    }
  }

  @override
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys) =>
      _inner.secureGetBatch(keys);

  @override
  Future<void> secureDeleteBatch(List<String> keys) async {
    await _inner.secureDeleteBatch(keys);
    for (final key in keys) {
      _emit(key, VaultEventType.deleted);
    }
  }

  @override
  Future<List<T>> secureSearch<T>(String query) =>
      _inner.secureSearch<T>(query);

  @override
  Future<List<T>> secureSearchAny<T>(String query) =>
      _inner.secureSearchAny<T>(query);

  @override
  Future<List<T>> secureSearchPrefix<T>(String prefix) =>
      _inner.secureSearchPrefix<T>(prefix);

  @override
  Future<Set<String>> searchKeys(String query) => _inner.searchKeys(query);

  @override
  Future<void> rebuildIndex() => _inner.rebuildIndex();

  @override
  Future<void> compact() => _inner.compact();

  @override
  void clearCache() => _inner.clearCache();

  @override
  Future<Uint8List> exportEncrypted() => _inner.exportEncrypted();

  @override
  Future<void> importEncrypted(Uint8List data) => _inner.importEncrypted(data);

  @override
  Future<VaultStats> getStats() => _inner.getStats();

  @override
  List<AuditEntry> getAuditLog({int limit = 50}) =>
      _inner.getAuditLog(limit: limit);
}
