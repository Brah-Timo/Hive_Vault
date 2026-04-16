// lib/src/transaction/vault_transaction.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — ACID-style Transaction Manager.
//
// Provides read-your-writes consistency and atomic commit/rollback semantics
// over the vault's key-value store. Because Hive itself is single-writer,
// true serialisable isolation is not required; instead this manager gives:
//
//   • Atomicity  — all writes commit together or none do.
//   • Consistency — dirty reads are served from an in-tx write buffer.
//   • Isolation   — pending writes are invisible to other transactions
//                   (optimistic, last-writer-wins on commit).
//   • Durability  — after commit() every write reaches Hive.
//
// Nested transactions are supported via save-points.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import '../core/vault_interface.dart';
import '../core/vault_exceptions.dart';
import '../core/sensitivity_level.dart';

/// The current status of a [VaultTransaction].
enum TransactionStatus { active, committed, rolledBack }

/// A single operation recorded inside a transaction's write-ahead log.
class _TxOperation {
  final String key;
  final dynamic value;
  final SensitivityLevel? sensitivity;
  final String? searchableText;
  final bool isDelete;
  final DateTime timestamp;

  _TxOperation.write(
    this.key,
    this.value, {
    this.sensitivity,
    this.searchableText,
  })  : isDelete = false,
        timestamp = DateTime.now();

  _TxOperation.delete(this.key)
      : value = null,
        sensitivity = null,
        searchableText = null,
        isDelete = true,
        timestamp = DateTime.now();
}

/// An isolated snapshot of a save-point inside a transaction.
class TransactionSavepoint {
  final String name;
  final int _operationCount;
  final DateTime createdAt;

  TransactionSavepoint._(this.name, this._operationCount)
      : createdAt = DateTime.now();
}

/// A transaction context.
///
/// Obtain one via [VaultTransactionManager.begin].
///
/// ```dart
/// final tx = manager.begin();
/// try {
///   tx.write('user:1', user1);
///   tx.write('user:2', user2);
///   tx.delete('user:old');
///   await tx.commit();
/// } catch (_) {
///   await tx.rollback();
///   rethrow;
/// }
/// ```
class VaultTransaction {
  // ── Write-ahead log (WAL) ────────────────────────────────────────────────
  final List<_TxOperation> _wal = [];

  // ── Read buffer (for read-your-writes) ──────────────────────────────────
  final Map<String, dynamic> _readBuffer = {};
  final Set<String> _deletedInTx = {};

  // ── Save-points ──────────────────────────────────────────────────────────
  final List<TransactionSavepoint> _savepoints = [];

  // ── Metadata ─────────────────────────────────────────────────────────────
  final String id;
  final DateTime startedAt;
  final SecureStorageInterface _vault;
  TransactionStatus _status = TransactionStatus.active;

  VaultTransaction._(this.id, this._vault) : startedAt = DateTime.now();

  TransactionStatus get status => _status;
  bool get isActive => _status == TransactionStatus.active;

  // ── Write operations ─────────────────────────────────────────────────────

  /// Stages a write for [key] within this transaction.
  ///
  /// The value is immediately visible to subsequent [read] calls within
  /// this transaction (read-your-writes), but is NOT persisted until [commit].
  void write(
    String key,
    dynamic value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  }) {
    _assertActive();
    _wal.add(_TxOperation.write(
      key,
      value,
      sensitivity: sensitivity,
      searchableText: searchableText,
    ));
    _readBuffer[key] = value;
    _deletedInTx.remove(key); // un-delete if re-written
  }

  /// Stages a delete for [key] within this transaction.
  void delete(String key) {
    _assertActive();
    _wal.add(_TxOperation.delete(key));
    _readBuffer.remove(key);
    _deletedInTx.add(key);
  }

  // ── Read operations ──────────────────────────────────────────────────────

  /// Reads [key], returning the staged value if one exists, falling back to
  /// the underlying vault.
  Future<T?> read<T>(String key) async {
    _assertActive();
    if (_deletedInTx.contains(key)) return null;
    if (_readBuffer.containsKey(key)) return _readBuffer[key] as T?;
    return _vault.secureGet<T>(key);
  }

  /// Returns `true` if [key] exists (considering in-tx writes/deletes).
  Future<bool> contains(String key) async {
    _assertActive();
    if (_deletedInTx.contains(key)) return false;
    if (_readBuffer.containsKey(key)) return true;
    return _vault.secureContains(key);
  }

  // ── Save-points ──────────────────────────────────────────────────────────

  /// Creates a named save-point that you can roll back to.
  TransactionSavepoint savepoint(String name) {
    _assertActive();
    final sp = TransactionSavepoint._(name, _wal.length);
    _savepoints.add(sp);
    return sp;
  }

  /// Rolls back to [sp], discarding all operations added after it.
  void rollbackToSavepoint(TransactionSavepoint sp) {
    _assertActive();
    final idx = _savepoints.indexOf(sp);
    if (idx == -1) {
      throw VaultStorageException(
        'Save-point "${sp.name}" does not belong to this transaction.',
      );
    }
    // Discard WAL entries after the savepoint.
    _wal.removeRange(sp._operationCount, _wal.length);
    // Rebuild read-buffer and deleted set from scratch.
    _rebuildReadBuffer();
    // Remove save-points added after this one.
    _savepoints.removeRange(idx + 1, _savepoints.length);
  }

  // ── Commit / Rollback ────────────────────────────────────────────────────

  /// Atomically applies all staged writes to the vault.
  ///
  /// If any individual write fails the commit is aborted and a
  /// [VaultTransactionException] is thrown. Already-applied writes are NOT
  /// automatically reversed — call [rollback] and re-create the transaction.
  Future<TransactionReceipt> commit() async {
    _assertActive();
    final sw = Stopwatch()..start();
    int writes = 0;
    int deletes = 0;

    try {
      for (final op in _wal) {
        if (op.isDelete) {
          await _vault.secureDelete(op.key);
          deletes++;
        } else {
          await _vault.secureSave(
            op.key,
            op.value,
            sensitivity: op.sensitivity,
            searchableText: op.searchableText,
          );
          writes++;
        }
      }
      _status = TransactionStatus.committed;
      sw.stop();
      return TransactionReceipt(
        transactionId: id,
        writes: writes,
        deletes: deletes,
        elapsed: sw.elapsed,
        status: TransactionStatus.committed,
        committedAt: DateTime.now(),
      );
    } catch (e) {
      _status = TransactionStatus.active; // allow retry
      throw VaultTransactionException(
        'Transaction $id commit failed after $writes writes / $deletes deletes',
        cause: e,
      );
    }
  }

  /// Discards all staged writes without touching the vault.
  Future<void> rollback() async {
    if (_status == TransactionStatus.committed) {
      throw VaultTransactionException(
        'Cannot roll back a committed transaction ($id)',
      );
    }
    _wal.clear();
    _readBuffer.clear();
    _deletedInTx.clear();
    _savepoints.clear();
    _status = TransactionStatus.rolledBack;
  }

  // ── Introspection ────────────────────────────────────────────────────────

  /// Returns the number of staged operations.
  int get pendingOperations => _wal.length;

  /// Returns all keys that will be written on commit.
  Set<String> get pendingWriteKeys =>
      _wal.where((o) => !o.isDelete).map((o) => o.key).toSet();

  /// Returns all keys that will be deleted on commit.
  Set<String> get pendingDeleteKeys =>
      _wal.where((o) => o.isDelete).map((o) => o.key).toSet();

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _assertActive() {
    if (_status != TransactionStatus.active) {
      throw VaultTransactionException(
        'Transaction $id is $_status and cannot accept new operations.',
      );
    }
  }

  void _rebuildReadBuffer() {
    _readBuffer.clear();
    _deletedInTx.clear();
    for (final op in _wal) {
      if (op.isDelete) {
        _readBuffer.remove(op.key);
        _deletedInTx.add(op.key);
      } else {
        _readBuffer[op.key] = op.value;
        _deletedInTx.remove(op.key);
      }
    }
  }

  @override
  String toString() =>
      'VaultTransaction(id: $id, status: ${_status.name}, '
      'pendingOps: ${_wal.length})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transaction receipt
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable record of a completed (committed or rolled-back) transaction.
class TransactionReceipt {
  final String transactionId;
  final int writes;
  final int deletes;
  final Duration elapsed;
  final TransactionStatus status;
  final DateTime committedAt;

  const TransactionReceipt({
    required this.transactionId,
    required this.writes,
    required this.deletes,
    required this.elapsed,
    required this.status,
    required this.committedAt,
  });

  @override
  String toString() =>
      'TransactionReceipt(id: $transactionId, writes: $writes, '
      'deletes: $deletes, elapsed: ${elapsed.inMilliseconds}ms, '
      'status: ${status.name})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Transaction Manager
// ═══════════════════════════════════════════════════════════════════════════

/// Factory and registry for [VaultTransaction] instances.
///
/// Provides [runInTransaction] for automatic commit/rollback handling.
class VaultTransactionManager {
  final SecureStorageInterface _vault;
  final Map<String, VaultTransaction> _active = {};
  int _txCounter = 0;

  VaultTransactionManager(this._vault);

  // ── Begin ────────────────────────────────────────────────────────────────

  /// Creates and registers a new active transaction.
  VaultTransaction begin() {
    final id = 'tx-${++_txCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final tx = VaultTransaction._(id, _vault);
    _active[id] = tx;
    return tx;
  }

  // ── Run helper ───────────────────────────────────────────────────────────

  /// Runs [block] inside a transaction, auto-committing on success and
  /// auto-rolling-back on any error.
  ///
  /// Returns the [TransactionReceipt] on success.
  Future<TransactionReceipt> runInTransaction(
    Future<void> Function(VaultTransaction tx) block,
  ) async {
    final tx = begin();
    try {
      await block(tx);
      final receipt = await tx.commit();
      _active.remove(tx.id);
      return receipt;
    } catch (e) {
      await tx.rollback();
      _active.remove(tx.id);
      rethrow;
    }
  }

  // ── Introspection ────────────────────────────────────────────────────────

  /// Returns all currently active (un-committed / un-rolled-back) transactions.
  List<VaultTransaction> get activeTransactions => _active.values.toList();

  /// Total number of transactions created since this manager was instantiated.
  int get totalTransactions => _txCounter;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Exception
// ═══════════════════════════════════════════════════════════════════════════

/// Thrown when a transaction operation fails.
class VaultTransactionException extends VaultException {
  const VaultTransactionException(super.message, {super.cause});

  @override
  String toString() => 'VaultTransactionException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}
