// test/integration/advanced_features_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Integration tests for TTL, ReactiveVault, MultiBoxVault, Health, Migration.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:test/test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_vault/hive_vault.dart';
import 'package:hive_vault/src/impl/reactive_vault.dart';
import 'package:hive_vault/src/impl/multi_box_vault.dart';
import 'package:hive_vault/src/impl/ttl_manager.dart';
import 'package:hive_vault/src/impl/vault_health.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_adv_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  ReactiveVault
  // ═══════════════════════════════════════════════════════════════════════════

  group('ReactiveVault', () {
    late ReactiveVault reactive;

    setUp(() async {
      final inner = await HiveVault.create(
        boxName: 'rv_${DateTime.now().microsecondsSinceEpoch}',
        config: VaultConfig.debug(),
      );
      await inner.initialize();
      reactive = ReactiveVault(inner);
    });

    tearDown(() async => reactive.close());

    test('emits saved event on secureSave', () async {
      final events = <VaultEvent>[];
      final sub = reactive.watchAll.listen(events.add);

      await reactive.secureSave('KEY-1', {'x': 1});
      await Future.delayed(const Duration(milliseconds: 10));

      expect(events, hasLength(1));
      expect(events.first.type, equals(VaultEventType.saved));
      expect(events.first.key, equals('KEY-1'));
      await sub.cancel();
    });

    test('emits deleted event on secureDelete', () async {
      await reactive.secureSave('DEL-1', {'x': 1});
      final events = <VaultEvent>[];
      final sub = reactive.watchAll.listen(events.add);

      await reactive.secureDelete('DEL-1');
      await Future.delayed(const Duration(milliseconds: 10));

      final deleteEvents =
          events.where((e) => e.type == VaultEventType.deleted).toList();
      expect(deleteEvents, hasLength(1));
      await sub.cancel();
    });

    test('watch(key) only emits for that key', () async {
      final events = <VaultEvent>[];
      final sub = reactive.watch('SPECIAL').listen(events.add);

      await reactive.secureSave('SPECIAL', {'v': 1});
      await reactive.secureSave('OTHER', {'v': 2});
      await Future.delayed(const Duration(milliseconds: 10));

      expect(events, hasLength(1));
      expect(events.first.key, equals('SPECIAL'));
      await sub.cancel();
    });

    test('batch save emits event for each key', () async {
      final events = <VaultEvent>[];
      final sub = reactive.watchAll.listen(events.add);

      await reactive.secureSaveBatch({'A': 1, 'B': 2, 'C': 3});
      await Future.delayed(const Duration(milliseconds: 10));

      final saveEvents =
          events.where((e) => e.type == VaultEventType.saved).toList();
      expect(saveEvents.length, equals(3));
      await sub.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  TtlManager
  // ═══════════════════════════════════════════════════════════════════════════

  group('TtlManager', () {
    late SecureStorageInterface vault;
    late TtlManager ttl;
    late String boxName;

    setUp(() async {
      boxName = 'ttl_${DateTime.now().microsecondsSinceEpoch}';
      vault = await HiveVault.open(
        boxName: boxName,
        config: VaultConfig.debug(),
      );
      ttl = TtlManager(dataBoxName: boxName);
      await ttl.initialize();
    });

    tearDown(() async {
      await ttl.close();
      await vault.close();
    });

    test('setExpiry and getExpiry work correctly', () async {
      await ttl.setExpiry('K1', const Duration(hours: 1));
      final expiry = ttl.getExpiry('K1');
      expect(expiry, isNotNull);
      expect(expiry!.isAfter(DateTime.now()), isTrue);
    });

    test('non-expired key returns isExpired = false', () async {
      await ttl.setExpiry('K2', const Duration(hours: 24));
      expect(ttl.isExpired('K2'), isFalse);
    });

    test('expired key returns isExpired = true', () async {
      await ttl.setExpiry('K3', const Duration(milliseconds: 1));
      await Future.delayed(const Duration(milliseconds: 5));
      expect(ttl.isExpired('K3'), isTrue);
    });

    test('purgeNow removes expired keys', () async {
      await vault.secureSave('EXP-1', {'x': 1});
      await vault.secureSave('EXP-2', {'x': 2});
      await vault.secureSave('KEEP', {'x': 3});

      await ttl.setExpiry('EXP-1', const Duration(milliseconds: 1));
      await ttl.setExpiry('EXP-2', const Duration(milliseconds: 1));
      await ttl.setExpiry('KEEP', const Duration(hours: 24));

      await Future.delayed(const Duration(milliseconds: 5));

      final purged = await ttl.purgeNow(
        onExpired: (key) => vault.secureDelete(key),
      );

      expect(purged, containsAll(['EXP-1', 'EXP-2']));
      expect(purged, isNot(contains('KEEP')));
      expect(await vault.secureContains('EXP-1'), isFalse);
      expect(await vault.secureContains('EXP-2'), isFalse);
      expect(await vault.secureContains('KEEP'), isTrue);
    });

    test('getRemaining returns positive duration for live key', () async {
      await ttl.setExpiry('LIVE', const Duration(hours: 1));
      final rem = ttl.getRemaining('LIVE');
      expect(rem, isNotNull);
      expect(rem!.inMinutes, greaterThan(55));
    });

    test('clearExpiry removes TTL', () async {
      await ttl.setExpiry('CLEAR-ME', const Duration(hours: 1));
      await ttl.clearExpiry('CLEAR-ME');
      expect(ttl.getExpiry('CLEAR-ME'), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  MultiBoxVault
  // ═══════════════════════════════════════════════════════════════════════════

  group('MultiBoxVault', () {
    late MultiBoxVault multi;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      multi = MultiBoxVault(
        defaultConfig: VaultConfig.debug(),
        modules: ['m_clients_$suffix', 'm_invoices_$suffix'],
      );
      await multi.initialize();
    });

    tearDown(() async => multi.close());

    test('module() returns the correct vault', () {
      final names = multi.moduleNames.toList();
      expect(names.length, equals(2));
    });

    test('each module is independent', () async {
      final names = multi.moduleNames.toList();
      await multi[names[0]].secureSave('K1', {'module': 'clients'});
      await multi[names[1]].secureSave('K1', {'module': 'invoices'});

      final c = await multi[names[0]].secureGet<Map>('K1');
      final i = await multi[names[1]].secureGet<Map>('K1');

      expect(c?['module'], equals('clients'));
      expect(i?['module'], equals('invoices'));
    });

    test('isOpen returns true for registered module', () {
      final firstName = multi.moduleNames.first;
      expect(multi.isOpen(firstName), isTrue);
    });

    test('accessing unregistered module throws VaultInitException', () {
      expect(
        () => multi['non_existent_module'],
        throwsA(isA<VaultInitException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  VaultHealthChecker
  // ═══════════════════════════════════════════════════════════════════════════

  group('VaultHealthChecker', () {
    test('returns HealthReport for an empty vault', () async {
      final vault = await HiveVault.open(
        boxName: 'health_${DateTime.now().microsecondsSinceEpoch}',
        config: VaultConfig.debug(),
      );
      final report = await VaultHealthChecker.check(vault);
      expect(report.checkedAt, isNotNull);
      expect(report.stats, isNotNull);
      await vault.close();
    });

    test('returns HealthReport with info for a populated vault', () async {
      final vault = await HiveVault.open(
        boxName: 'health2_${DateTime.now().microsecondsSinceEpoch}',
        config: VaultConfig.debug(),
      );
      for (int i = 0; i < 10; i++) {
        await vault.secureSave('H-$i', {'id': i});
      }
      final report = await VaultHealthChecker.check(vault);
      expect(report, isNotNull);
      expect(report.issues, isNotEmpty);
      await vault.close();
    });

    test('healthy vault has no critical issues', () async {
      final vault = await HiveVault.open(
        boxName: 'health3_${DateTime.now().microsecondsSinceEpoch}',
        config: VaultConfig.debug(),
      );
      for (int i = 0; i < 5; i++) {
        await vault.secureSave('K-$i', {'n': i}, searchableText: 'item $i');
      }
      for (int i = 0; i < 5; i++) {
        await vault.secureGet<Map>('K-$i');
      }
      final report = await VaultHealthChecker.check(vault);
      expect(report.hasCritical, isFalse);
      await vault.close();
    });
  });
}
