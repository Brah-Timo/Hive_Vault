// test/plugin/vault_plugin_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for the HiveVault Plugin System.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/plugin/vault_plugin.dart';

// ── Stub vault ────────────────────────────────────────────────────────────────
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
  @override Future<VaultStats> getStats() async => VaultStats(boxName: 'test', totalEntries: 0, cacheSize: 0, cacheCapacity: 0, cacheHitRatio: 0, compressionAlgorithm: 'None', encryptionAlgorithm: 'None', indexStats: const IndexStats.empty(), totalBytesSaved: 0, totalBytesWritten: 0, totalWrites: 0, totalReads: 0, totalSearches: 0, openedAt: DateTime.now());
  @override List<AuditEntry> getAuditLog({int limit = 50}) => [];
}

// ── Spy plugin ────────────────────────────────────────────────────────────────

class _SpyPlugin extends VaultPlugin {
  @override String get name => 'spy';
  final List<String> calls = [];

  @override Future<void> beforeSave(PluginContext ctx) async => calls.add('beforeSave:${ctx.key}');
  @override Future<void> afterSave(PluginContext ctx) async => calls.add('afterSave:${ctx.key}');
  @override Future<void> beforeGet(PluginContext ctx) async => calls.add('beforeGet:${ctx.key}');
  @override Future<void> afterGet(PluginContext ctx) async => calls.add('afterGet:${ctx.key}');
  @override Future<void> beforeDelete(PluginContext ctx) async => calls.add('beforeDelete:${ctx.key}');
  @override Future<void> afterDelete(PluginContext ctx) async => calls.add('afterDelete:${ctx.key}');
  @override Future<void> onError(PluginContext ctx, Object e) async => calls.add('onError:${ctx.key}');
}

void main() {
  late _StubVault inner;
  late PluggableVault vault;
  late _SpyPlugin spy;

  setUp(() {
    inner = _StubVault();
    spy = _SpyPlugin();
    vault = PluggableVault(inner: inner)..use(spy);
  });

  // ── PluginRegistry ────────────────────────────────────────────────────────

  group('PluginRegistry', () {
    test('registers and sorts by priority', () {
      final registry = PluginRegistry();
      final p1 = ConsoleLoggingPlugin(); // priority 10
      final p2 = SchemaValidationPlugin(requiredFields: {}); // priority 5
      registry.register(p1);
      registry.register(p2);
      expect(registry.all.first.priority, equals(5));
    });

    test('find returns null for unknown name', () {
      final registry = PluginRegistry();
      expect(registry.find('nonexistent'), isNull);
    });

    test('unregister removes plugin by name', () {
      final registry = PluginRegistry();
      registry.register(ConsoleLoggingPlugin());
      registry.unregister('console_logging');
      expect(registry.count, equals(0));
    });
  });

  // ── PluggableVault hooks ──────────────────────────────────────────────────

  group('PluggableVault hooks', () {
    test('beforeSave and afterSave are called', () async {
      await vault.secureSave('myKey', 'myValue');
      expect(spy.calls, containsAll(['beforeSave:myKey', 'afterSave:myKey']));
    });

    test('beforeGet and afterGet are called', () async {
      inner.data['k'] = 'v';
      await vault.secureGet<String>('k');
      expect(spy.calls, containsAll(['beforeGet:k', 'afterGet:k']));
    });

    test('beforeDelete and afterDelete are called', () async {
      inner.data['del'] = 'x';
      await vault.secureDelete('del');
      expect(spy.calls, containsAll(['beforeDelete:del', 'afterDelete:del']));
    });

    test('cancelled save does not reach inner vault', () async {
      final cancelPlugin = _CancelSavePlugin();
      vault.use(cancelPlugin);
      expect(
        () => vault.secureSave('blocked', 'value'),
        throwsA(isA<VaultPluginException>()),
      );
      expect(inner.data.containsKey('blocked'), isFalse);
    });

    test('cancelled get returns null', () async {
      inner.data['secret'] = 'hidden';
      final cancelPlugin = _CancelGetPlugin();
      final v2 = PluggableVault(inner: inner)..use(cancelPlugin);
      final result = await v2.secureGet<String>('secret');
      expect(result, isNull);
    });
  });

  // ── FieldMaskingPlugin ────────────────────────────────────────────────────

  group('FieldMaskingPlugin', () {
    test('masks specified fields before saving', () async {
      final masker = FieldMaskingPlugin(maskedFields: {'password', 'ssn'});
      final v = PluggableVault(inner: inner)..use(masker);
      await v.secureSave('user:1', {
        'name': 'Alice',
        'password': 'secret123',
        'ssn': '000-00-0000',
      });
      final saved = inner.data['user:1'] as Map<String, dynamic>;
      expect(saved['password'], equals('***'));
      expect(saved['ssn'], equals('***'));
      expect(saved['name'], equals('Alice'));
    });

    test('non-Map values are not affected', () async {
      final masker = FieldMaskingPlugin(maskedFields: {'password'});
      final v = PluggableVault(inner: inner)..use(masker);
      await v.secureSave('str:1', 'plain string');
      expect(inner.data['str:1'], equals('plain string'));
    });
  });

  // ── SchemaValidationPlugin ────────────────────────────────────────────────

  group('SchemaValidationPlugin', () {
    test('valid record passes through', () async {
      final validator = SchemaValidationPlugin(
        requiredFields: {'name': String, 'age': int},
      );
      final v = PluggableVault(inner: inner)..use(validator);
      await v.secureSave('u', {'name': 'Bob', 'age': 30});
      expect(inner.data['u'], isNotNull);
    });

    test('missing required field cancels save', () async {
      final validator = SchemaValidationPlugin(
        requiredFields: {'name': String, 'email': String},
      );
      final v = PluggableVault(inner: inner)..use(validator);
      expect(
        () => v.secureSave('u', {'name': 'Bob'}),
        throwsA(isA<VaultPluginException>()),
      );
    });

    test('wrong type cancels save', () async {
      final validator = SchemaValidationPlugin(
        requiredFields: {'age': int},
      );
      final v = PluggableVault(inner: inner)..use(validator);
      expect(
        () => v.secureSave('u', {'age': '30'}), // String instead of int
        throwsA(isA<VaultPluginException>()),
      );
    });
  });

  // ── TimingPlugin ──────────────────────────────────────────────────────────

  group('TimingPlugin', () {
    test('records save timings', () async {
      final timer = TimingPlugin();
      final v = PluggableVault(inner: inner)..use(timer);
      await v.secureSave('k', 'v');
      expect(timer.averageUs('save'), greaterThanOrEqualTo(0));
    });
  });

  // ── KeyNamingPlugin ───────────────────────────────────────────────────────

  group('KeyNamingPlugin', () {
    test('allows conforming keys', () async {
      final naming = KeyNamingPlugin(
        pattern: RegExp(r'^[a-z]+:\d+$'),
        description: 'entity:id format',
      );
      final v = PluggableVault(inner: inner)..use(naming);
      await v.secureSave('user:42', 'data');
      expect(inner.data.containsKey('user:42'), isTrue);
    });

    test('rejects non-conforming keys', () async {
      final naming = KeyNamingPlugin(
        pattern: RegExp(r'^[a-z]+:\d+$'),
        description: 'entity:id format',
      );
      final v = PluggableVault(inner: inner)..use(naming);
      expect(
        () => v.secureSave('INVALID_KEY', 'data'),
        throwsA(isA<VaultPluginException>()),
      );
    });
  });
}

// ── Helper plugin stubs ───────────────────────────────────────────────────────

class _CancelSavePlugin extends VaultPlugin {
  @override String get name => 'cancel_save';
  @override int get priority => 1;
  @override Future<void> beforeSave(PluginContext ctx) async {
    ctx.cancelled = true;
    ctx.cancellationReason = 'test cancellation';
  }
}

class _CancelGetPlugin extends VaultPlugin {
  @override String get name => 'cancel_get';
  @override Future<void> beforeGet(PluginContext ctx) async {
    ctx.cancelled = true;
  }
}
