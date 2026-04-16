// test/transaction/vault_transaction_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for the HiveVault Transaction Manager.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/transaction/vault_transaction.dart';
import '../../lib/src/core/vault_exceptions.dart';

// ── Minimal in-memory stub vault ──────────────────────────────────────────────
import 'dart:typed_data';
import '../../lib/src/core/vault_interface.dart';
import '../../lib/src/core/sensitivity_level.dart';
import '../../lib/src/core/vault_stats.dart';
import '../../lib/src/audit/audit_entry.dart';

class _StubVault implements SecureStorageInterface {
  final Map<String, dynamic> data = {};

  @override Future<void> initialize() async {}
  @override Future<void> close() async {}
  @override Future<bool> secureContains(String k) async => data.containsKey(k);
  @override Future<List<String>> getAllKeys() async => data.keys.toList();
  @override Future<T?> secureGet<T>(String k) async => data[k] as T?;
  @override Future<void> secureDelete(String k) async => data.remove(k);
  @override Future<void> secureSave<T>(String k, T v, {SensitivityLevel? sensitivity, String? searchableText}) async => data[k] = v;
  @override Future<void> secureSaveBatch(Map<String, dynamic> e, {SensitivityLevel? sensitivity}) async => data.addAll(e);
  @override Future<Map<String, dynamic>> secureGetBatch(List<String> ks) async => {for (final k in ks) if (data.containsKey(k)) k: data[k]};
  @override Future<void> secureDeleteBatch(List<String> ks) async => ks.forEach(data.remove);
  @override Future<List<T>> secureSearch<T>(String q) async => [];
  @override Future<List<T>> secureSearchAny<T>(String q) async => [];
  @override Future<List<T>> secureSearchPrefix<T>(String p) async => [];
  @override Future<Set<String>> searchKeys(String q) async => {};
  @override Future<void> rebuildIndex() async {}
  @override Future<void> compact() async {}
  @override void clearCache() {}
  @override Future<Uint8List> exportEncrypted() async => Uint8List(0);
  @override Future<void> importEncrypted(Uint8List d) async {}
  @override Future<VaultStats> getStats() async => VaultStats(boxName: 'test', totalEntries: data.length, cacheSize: 0, cacheCapacity: 0, cacheHitRatio: 0, compressionAlgorithm: 'None', encryptionAlgorithm: 'None', indexStats: const IndexStats.empty(), totalBytesSaved: 0, totalBytesWritten: 0, totalWrites: 0, totalReads: 0, totalSearches: 0, openedAt: DateTime.now());
  @override List<AuditEntry> getAuditLog({int limit = 50}) => [];
}

void main() {
  late _StubVault vault;
  late VaultTransactionManager manager;

  setUp(() {
    vault = _StubVault();
    manager = VaultTransactionManager(vault);
  });

  // ── VaultTransaction ──────────────────────────────────────────────────────

  group('VaultTransaction', () {
    test('begins in active state', () {
      final tx = manager.begin();
      expect(tx.status, equals(TransactionStatus.active));
      expect(tx.isActive, isTrue);
    });

    test('write stages value in read buffer', () async {
      final tx = manager.begin();
      tx.write('key1', 'value1');
      expect(await tx.read<String>('key1'), equals('value1'));
    });

    test('delete marks key as deleted', () async {
      final tx = manager.begin();
      tx.write('key1', 'value1');
      tx.delete('key1');
      expect(await tx.contains('key1'), isFalse);
      expect(await tx.read<String>('key1'), isNull);
    });

    test('re-writing a deleted key restores it', () async {
      final tx = manager.begin();
      tx.write('key1', 'original');
      tx.delete('key1');
      tx.write('key1', 'restored');
      expect(await tx.read<String>('key1'), equals('restored'));
    });

    test('commit applies all writes to vault', () async {
      final tx = manager.begin();
      tx.write('a', 1);
      tx.write('b', 2);
      await tx.commit();
      expect(vault.data['a'], equals(1));
      expect(vault.data['b'], equals(2));
      expect(tx.status, equals(TransactionStatus.committed));
    });

    test('commit applies deletes to vault', () async {
      vault.data['existing'] = 'will-be-deleted';
      final tx = manager.begin();
      tx.delete('existing');
      await tx.commit();
      expect(vault.data.containsKey('existing'), isFalse);
    });

    test('commit returns receipt with correct counts', () async {
      final tx = manager.begin();
      tx.write('w1', 'v1');
      tx.write('w2', 'v2');
      tx.delete('d1'); // key doesn't exist in vault but delete is still called
      final receipt = await tx.commit();
      expect(receipt.writes, equals(2));
      expect(receipt.deletes, equals(1));
      expect(receipt.status, equals(TransactionStatus.committed));
    });

    test('rollback discards all staged writes', () async {
      final tx = manager.begin();
      tx.write('should-not-persist', 42);
      await tx.rollback();
      expect(vault.data.containsKey('should-not-persist'), isFalse);
      expect(tx.status, equals(TransactionStatus.rolledBack));
    });

    test('operations on committed tx throw', () async {
      final tx = manager.begin();
      tx.write('k', 'v');
      await tx.commit();
      expect(() => tx.write('k2', 'v2'), throwsA(isA<VaultTransactionException>()));
    });

    test('read falls through to vault when not in buffer', () async {
      vault.data['persistent'] = 'hello';
      final tx = manager.begin();
      expect(await tx.read<String>('persistent'), equals('hello'));
    });

    test('pendingOperations count is correct', () {
      final tx = manager.begin();
      tx.write('a', 1);
      tx.write('b', 2);
      tx.delete('c');
      expect(tx.pendingOperations, equals(3));
    });

    test('pendingWriteKeys and pendingDeleteKeys', () {
      final tx = manager.begin();
      tx.write('w1', 1);
      tx.write('w2', 2);
      tx.delete('d1');
      expect(tx.pendingWriteKeys, containsAll(['w1', 'w2']));
      expect(tx.pendingDeleteKeys, contains('d1'));
    });
  });

  // ── Save-points ───────────────────────────────────────────────────────────

  group('TransactionSavepoint', () {
    test('rollbackToSavepoint discards ops after savepoint', () async {
      final tx = manager.begin();
      tx.write('a', 1);
      final sp = tx.savepoint('sp1');
      tx.write('b', 2);
      tx.write('c', 3);
      tx.rollbackToSavepoint(sp);
      expect(tx.pendingOperations, equals(1));
      expect(await tx.read<int>('a'), equals(1));
      expect(await tx.read<int>('b'), isNull); // rolled back
    });

    test('savepoint from wrong tx throws', () {
      final tx1 = manager.begin();
      final tx2 = manager.begin();
      final sp = tx1.savepoint('sp');
      expect(() => tx2.rollbackToSavepoint(sp),
          throwsA(isA<VaultStorageException>()));
    });
  });

  // ── VaultTransactionManager ───────────────────────────────────────────────

  group('VaultTransactionManager', () {
    test('runInTransaction commits on success', () async {
      final receipt = await manager.runInTransaction((tx) async {
        tx.write('managed_key', 'managed_val');
      });
      expect(vault.data['managed_key'], equals('managed_val'));
      expect(receipt.status, equals(TransactionStatus.committed));
    });

    test('runInTransaction rolls back on error', () async {
      try {
        await manager.runInTransaction((tx) async {
          tx.write('should-rollback', 'value');
          throw Exception('simulated error');
        });
      } catch (_) {}
      expect(vault.data.containsKey('should-rollback'), isFalse);
    });

    test('totalTransactions increments', () {
      manager.begin();
      manager.begin();
      expect(manager.totalTransactions, equals(2));
    });

    test('activeTransactions tracks open transactions', () {
      final tx = manager.begin();
      expect(manager.activeTransactions, contains(tx));
    });
  });
}
