// test/integration/vault_integration_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Integration tests for HiveVaultImpl using VaultConfig.debug()
// (no encryption, no compression) to keep tests fast and deterministic.
//
// For tests involving real encryption/compression see the encryption/ and
// compression/ test directories.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:io';
import 'package:test/test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_vault/hive_vault.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────────────────────
// Test fixtures
// ─────────────────────────────────────────────────────────────────────────────

final _invoice1 = {
  'number': 'INV-2026-001',
  'client': 'Ahmed Mekraji',
  'amount': 125000.00,
  'date': '2026-04-16',
  'items': [
    {'name': 'Laptop', 'qty': 2, 'price': 55000},
    {'name': 'Printer', 'qty': 1, 'price': 15000},
  ],
};

final _invoice2 = {
  'number': 'INV-2026-002',
  'client': 'Mohamed Djelloul',
  'amount': 78500.00,
  'date': '2026-04-17',
  'items': [
    {'name': 'Monitor', 'qty': 3, 'price': 22500},
  ],
};

final _invoice3 = {
  'number': 'INV-2026-003',
  'client': 'Karima Boudiaf',
  'amount': 34000.00,
  'date': '2026-04-18',
  'items': [
    {'name': 'Keyboard', 'qty': 10, 'price': 2800},
  ],
};

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  late HiveVaultImpl vault;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_vault_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    final boxName = 'test_${DateTime.now().microsecondsSinceEpoch}';
    vault = await HiveVault.create(
      boxName: boxName,
      config: VaultConfig.debug(), // No encryption, no compression
    );
    await vault.initialize();
  });

  tearDown(() async {
    await vault.close();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Basic CRUD
  // ════════════════════════════════════════════════════════════════════════════

  group('CRUD — secureSave / secureGet', () {
    test('saves and retrieves a Map', () async {
      await vault.secureSave('INV-001', _invoice1);
      final result = await vault.secureGet<Map>('INV-001');
      expect(result, isNotNull);
      expect(result!['number'], equals('INV-2026-001'));
      expect(result['client'], equals('Ahmed Mekraji'));
      expect(result['amount'], equals(125000.00));
    });

    test('saves and retrieves a String', () async {
      await vault.secureSave('str-001', 'Hello HiveVault!');
      final result = await vault.secureGet<String>('str-001');
      expect(result, equals('Hello HiveVault!'));
    });

    test('saves and retrieves a List', () async {
      final list = [1, 2, 3, 'four', true];
      await vault.secureSave('list-001', list);
      final result = await vault.secureGet<List>('list-001');
      expect(result, equals(list));
    });

    test('secureGet returns null for non-existent key', () async {
      final result = await vault.secureGet<Map>('ghost-key');
      expect(result, isNull);
    });

    test('secureContains returns true after save', () async {
      await vault.secureSave('exists', 'yes');
      expect(await vault.secureContains('exists'), isTrue);
    });

    test('secureContains returns false before save', () async {
      expect(await vault.secureContains('never-saved'), isFalse);
    });

    test('saves and retrieves Arabic text content', () async {
      final arabicInvoice = {
        'رقم': 'INV-2026-099',
        'عميل': 'أحمد مقرادجي',
        'مبلغ': 99500.0,
        'تاريخ': '2026-04-16',
      };
      await vault.secureSave('ar-001', arabicInvoice);
      final result = await vault.secureGet<Map>('ar-001');
      expect(result!['عميل'], equals('أحمد مقرادجي'));
    });

    test('overwrite an existing key', () async {
      await vault.secureSave('key', {'v': 1});
      await vault.secureSave('key', {'v': 2});
      final result = await vault.secureGet<Map>('key');
      expect(result!['v'], equals(2));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Delete
  // ════════════════════════════════════════════════════════════════════════════

  group('Delete', () {
    test('secureDelete removes entry', () async {
      await vault.secureSave('del-key', {'x': 1});
      await vault.secureDelete('del-key');
      expect(await vault.secureContains('del-key'), isFalse);
    });

    test('secureGet after delete returns null', () async {
      await vault.secureSave('del-key2', 'value');
      await vault.secureDelete('del-key2');
      expect(await vault.secureGet<String>('del-key2'), isNull);
    });

    test('delete removes from index', () async {
      await vault.secureSave(
        'del-idx',
        {'name': 'ToDelete'},
        searchableText: 'unique-deletable-token',
      );
      final before = await vault.secureSearch<Map>('unique-deletable-token');
      expect(before, hasLength(1));
      await vault.secureDelete('del-idx');
      final after = await vault.secureSearch<Map>('unique-deletable-token');
      expect(after, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Batch operations
  // ════════════════════════════════════════════════════════════════════════════

  group('Batch operations', () {
    test('secureSaveBatch and secureGetBatch', () async {
      await vault.secureSaveBatch({
        'B-001': _invoice1,
        'B-002': _invoice2,
        'B-003': _invoice3,
      });

      final results = await vault.secureGetBatch(['B-001', 'B-002', 'B-003']);
      expect(results.length, equals(3));
      expect(results['B-001']['client'], equals('Ahmed Mekraji'));
      expect(results['B-002']['client'], equals('Mohamed Djelloul'));
      expect(results['B-003']['client'], equals('Karima Boudiaf'));
    });

    test('secureGetBatch skips missing keys', () async {
      await vault.secureSave('EXISTS', {'v': 1});
      final results = await vault.secureGetBatch(['EXISTS', 'MISSING']);
      expect(results.containsKey('EXISTS'), isTrue);
      expect(results.containsKey('MISSING'), isFalse);
    });

    test('secureDeleteBatch deletes all specified keys', () async {
      await vault.secureSaveBatch({'X': 1, 'Y': 2, 'Z': 3});
      await vault.secureDeleteBatch(['X', 'Y']);
      expect(await vault.secureContains('X'), isFalse);
      expect(await vault.secureContains('Y'), isFalse);
      expect(await vault.secureContains('Z'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Search
  // ════════════════════════════════════════════════════════════════════════════

  group('Search', () {
    setUp(() async {
      await vault.secureSave(
        'INV-001',
        _invoice1,
        searchableText: 'INV-2026-001 Ahmed Mekraji Laptop Printer invoice',
      );
      await vault.secureSave(
        'INV-002',
        _invoice2,
        searchableText: 'INV-2026-002 Mohamed Djelloul Monitor invoice',
      );
      await vault.secureSave(
        'INV-003',
        _invoice3,
        searchableText: 'INV-2026-003 Karima Boudiaf Keyboard invoice',
      );
    });

    test('secureSearch (AND): finds by single token', () async {
      final results = await vault.secureSearch<Map>('Ahmed');
      expect(results.length, equals(1));
      expect(results.first['client'], equals('Ahmed Mekraji'));
    });

    test('secureSearch (AND): finds by multiple tokens', () async {
      final results = await vault.secureSearch<Map>('Ahmed Laptop');
      expect(results.length, equals(1));
    });

    test('secureSearch (AND): returns empty for non-existent token', () async {
      final results = await vault.secureSearch<Map>('NonExistentToken');
      expect(results, isEmpty);
    });

    test('secureSearchAny (OR): returns union', () async {
      final results = await vault.secureSearchAny<Map>('Ahmed Mohamed');
      expect(results.length, equals(2));
    });

    test('secureSearchPrefix: finds by prefix', () async {
      final results = await vault.secureSearchPrefix<Map>('INV-2026');
      expect(results.length, equals(3));
    });

    test('secureSearchPrefix: empty prefix returns empty', () async {
      expect(await vault.secureSearchPrefix<Map>(''), isEmpty);
    });

    test('searchKeys returns keys only', () async {
      final keys = await vault.searchKeys('Ahmed');
      expect(keys, contains('INV-001'));
      expect(keys.length, equals(1));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  getAllKeys
  // ════════════════════════════════════════════════════════════════════════════

  group('getAllKeys', () {
    test('returns all stored keys', () async {
      await vault.secureSave('K1', 'a');
      await vault.secureSave('K2', 'b');
      final keys = await vault.getAllKeys();
      expect(keys, containsAll(['K1', 'K2']));
    });

    test('returns empty list for empty vault', () async {
      final keys = await vault.getAllKeys();
      expect(keys, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  rebuildIndex
  // ════════════════════════════════════════════════════════════════════════════

  group('rebuildIndex', () {
    test('rebuilds index — search works after rebuild', () async {
      await vault.secureSave(
        'RB-001',
        {'name': 'Rebuild Test'},
        searchableText: 'unique rebuild test token',
      );
      await vault.rebuildIndex();
      final results = await vault.secureSearch<Map>('unique');
      expect(results, hasLength(1));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  getStats
  // ════════════════════════════════════════════════════════════════════════════

  group('getStats', () {
    test('stats reflect write and read counts', () async {
      await vault.secureSave('S1', {'x': 1});
      await vault.secureGet<Map>('S1');
      final stats = await vault.getStats();
      expect(stats.totalWrites, greaterThanOrEqualTo(1));
      expect(stats.totalReads, greaterThanOrEqualTo(1));
    });

    test('stats.totalEntries matches box size', () async {
      await vault.secureSave('E1', 'a');
      await vault.secureSave('E2', 'b');
      final stats = await vault.getStats();
      expect(stats.totalEntries, greaterThanOrEqualTo(2));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Audit log
  // ════════════════════════════════════════════════════════════════════════════

  group('Audit log', () {
    test('audit log records save operations', () async {
      await vault.secureSave('AUD-1', {'x': 1});
      final log = vault.getAuditLog();
      final saveEntries = log.where((e) => e.action == AuditAction.save);
      expect(saveEntries, isNotEmpty);
    });

    test('audit log records get operations', () async {
      await vault.secureSave('AUD-2', {'y': 2});
      await vault.secureGet<Map>('AUD-2');
      final log = vault.getAuditLog();
      final getEntries = log.where((e) => e.action == AuditAction.get);
      expect(getEntries, isNotEmpty);
    });

    test('audit log records delete operations', () async {
      await vault.secureSave('AUD-3', {'z': 3});
      await vault.secureDelete('AUD-3');
      final log = vault.getAuditLog();
      final delEntries = log.where((e) => e.action == AuditAction.delete);
      expect(delEntries, isNotEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Cache behaviour
  // ════════════════════════════════════════════════════════════════════════════

  group('LRU Cache', () {
    test('second read is served from cache (fromCache = true in audit)',
        () async {
      final cacheVault = await HiveVault.create(
        boxName: 'cache_test_${DateTime.now().microsecondsSinceEpoch}',
        config: VaultConfig.debug().copyWith(
          enableMemoryCache: true,
          memoryCacheSize: 10,
        ),
      );
      await cacheVault.initialize();

      await cacheVault.secureSave('C1', {'v': 99});
      await cacheVault.secureGet<Map>('C1'); // miss (loads from Hive)
      await cacheVault.secureGet<Map>('C1'); // hit (from cache)

      final log = cacheVault.getAuditLog();
      final cacheHits = log.where((e) => e.fromCache);
      expect(cacheHits, isNotEmpty);
      await cacheVault.close();
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Edge cases
  // ════════════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('saves and retrieves empty map', () async {
      await vault.secureSave('empty-map', <String, dynamic>{});
      final result = await vault.secureGet<Map>('empty-map');
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('saves and retrieves empty string', () async {
      await vault.secureSave('empty-str', '');
      final result = await vault.secureGet<String>('empty-str');
      expect(result, equals(''));
    });

    test('saves and retrieves Unicode emoji content', () async {
      const content = '🚀 Flutter + HiveVault = 🔒';
      await vault.secureSave('emoji', content);
      final result = await vault.secureGet<String>('emoji');
      expect(result, equals(content));
    });

    test('large payload (50KB) saves and retrieves correctly', () async {
      final large = {
        'data': 'X' * 50000,
        'meta': {'size': 50000},
      };
      await vault.secureSave('large', large);
      final result = await vault.secureGet<Map>('large');
      expect((result!['data'] as String).length, equals(50000));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  //  Performance baseline
  // ════════════════════════════════════════════════════════════════════════════

  group('Performance', () {
    test('100 sequential writes complete in < 2 seconds', () async {
      final sw = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await vault.secureSave('perf-$i', {
          'id': i,
          'name': 'Item $i',
          'value': i * 99.9,
        });
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: '100 sequential writes should be < 2s',
      );
    });

    test('100 sequential reads complete in < 1 second', () async {
      for (int i = 0; i < 100; i++) {
        await vault.secureSave('read-$i', {'id': i});
      }
      final sw = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await vault.secureGet<Map>('read-$i');
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}
