// test/query/query_dsl_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for the HiveVault Query DSL.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/query/query_dsl.dart';
import '../../lib/src/core/vault_exceptions.dart';

// ── Minimal in-memory stub vault for testing ─────────────────────────────────
import 'dart:typed_data';
import '../../lib/src/core/vault_interface.dart';
import '../../lib/src/core/sensitivity_level.dart';
import '../../lib/src/core/vault_stats.dart';
import '../../lib/src/audit/audit_entry.dart';

class _StubVault implements SecureStorageInterface {
  final Map<String, dynamic> _store;
  _StubVault(this._store);

  @override Future<void> initialize() async {}
  @override Future<void> close() async {}
  @override Future<bool> secureContains(String k) async => _store.containsKey(k);
  @override Future<List<String>> getAllKeys() async => _store.keys.toList();
  @override Future<T?> secureGet<T>(String k) async => _store[k] as T?;
  @override Future<void> secureDelete(String k) async => _store.remove(k);
  @override Future<void> secureSave<T>(String k, T v, {SensitivityLevel? sensitivity, String? searchableText}) async => _store[k] = v;
  @override Future<void> secureSaveBatch(Map<String, dynamic> e, {SensitivityLevel? sensitivity}) async => _store.addAll(e);
  @override Future<Map<String, dynamic>> secureGetBatch(List<String> ks) async => {for (final k in ks) if (_store.containsKey(k)) k: _store[k]};
  @override Future<void> secureDeleteBatch(List<String> ks) async => ks.forEach(_store.remove);
  @override Future<List<T>> secureSearch<T>(String q) async => [];
  @override Future<List<T>> secureSearchAny<T>(String q) async => [];
  @override Future<List<T>> secureSearchPrefix<T>(String p) async => [];
  @override Future<Set<String>> searchKeys(String q) async => {};
  @override Future<void> rebuildIndex() async {}
  @override Future<void> compact() async {}
  @override void clearCache() {}
  @override Future<Uint8List> exportEncrypted() async => Uint8List(0);
  @override Future<void> importEncrypted(Uint8List d) async {}
  @override Future<VaultStats> getStats() async => VaultStats(boxName: 'test', totalEntries: _store.length, cacheSize: 0, cacheCapacity: 0, cacheHitRatio: 0, compressionAlgorithm: 'None', encryptionAlgorithm: 'None', indexStats: const IndexStats.empty(), totalBytesSaved: 0, totalBytesWritten: 0, totalWrites: 0, totalReads: 0, totalSearches: 0, openedAt: DateTime.now());
  @override List<AuditEntry> getAuditLog({int limit = 50}) => [];
}

// ── Sample data ───────────────────────────────────────────────────────────────

Map<String, dynamic> _emp(String id, String name, String dept, int salary, String role, {bool? active}) => {
  'id': id, 'name': name, 'department': dept, 'salary': salary, 'role': role,
  'active': active ?? true,
};

void main() {
  late _StubVault vault;

  setUp(() {
    vault = _StubVault({
      'emp:1': _emp('1', 'Alice',   'Engineering', 95000, 'Senior Engineer'),
      'emp:2': _emp('2', 'Bob',     'Engineering', 72000, 'Engineer'),
      'emp:3': _emp('3', 'Charlie', 'Sales',       65000, 'Account Executive'),
      'emp:4': _emp('4', 'Diana',   'Engineering', 110000,'Staff Engineer'),
      'emp:5': _emp('5', 'Eve',     'HR',          58000, 'HR Manager', active: false),
    });
  });

  // ── Predicate evaluation ─────────────────────────────────────────────────

  group('QueryPredicate', () {
    test('equals matches exact value', () {
      final pred = QueryPredicate(
        field: 'department', op: ComparisonOp.equals,
        value: 'Engineering', combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'department': 'Engineering'}), isTrue);
      expect(pred.evaluate({'department': 'Sales'}), isFalse);
    });

    test('greaterThan compares numerics', () {
      final pred = QueryPredicate(
        field: 'salary', op: ComparisonOp.greaterThan,
        value: 80000, combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'salary': 95000}), isTrue);
      expect(pred.evaluate({'salary': 72000}), isFalse);
    });

    test('contains is case-insensitive', () {
      final pred = QueryPredicate(
        field: 'role', op: ComparisonOp.contains,
        value: 'engineer', combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'role': 'Senior Engineer'}), isTrue);
      expect(pred.evaluate({'role': 'HR Manager'}), isFalse);
    });

    test('between is inclusive', () {
      final pred = QueryPredicate(
        field: 'salary', op: ComparisonOp.between,
        value: 70000, value2: 100000, combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'salary': 70000}), isTrue);
      expect(pred.evaluate({'salary': 100000}), isTrue);
      expect(pred.evaluate({'salary': 65000}), isFalse);
    });

    test('isIn membership check', () {
      final pred = QueryPredicate(
        field: 'department', op: ComparisonOp.isIn,
        value: ['Engineering', 'HR'], combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'department': 'Engineering'}), isTrue);
      expect(pred.evaluate({'department': 'Sales'}), isFalse);
    });

    test('isNull and isNotNull', () {
      final isNull = QueryPredicate(
        field: 'manager', op: ComparisonOp.isNull,
        combinator: PredicateCombinator.and,
      );
      expect(isNull.evaluate({'manager': null}), isTrue);
      expect(isNull.evaluate({'manager': 'Alice'}), isFalse);
    });

    test('regex matching', () {
      final pred = QueryPredicate(
        field: 'name', op: ComparisonOp.regex,
        value: r'^A', combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'name': 'Alice'}), isTrue);
      expect(pred.evaluate({'name': 'alice'}), isTrue); // caseSensitive: false
      expect(pred.evaluate({'name': 'Bob'}), isFalse);
    });

    test('dot-notation nested field access', () {
      final pred = QueryPredicate(
        field: 'address.city', op: ComparisonOp.equals,
        value: 'London', combinator: PredicateCombinator.and,
      );
      expect(pred.evaluate({'address': {'city': 'London'}}), isTrue);
      expect(pred.evaluate({'address': {'city': 'Paris'}}), isFalse);
    });
  });

  // ── SortSpec ─────────────────────────────────────────────────────────────

  group('SortSpec', () {
    test('ascending sorts correctly', () {
      final spec = SortSpec('salary');
      final a = {'salary': 72000};
      final b = {'salary': 95000};
      expect(spec.compare(a, b), lessThan(0));
      expect(spec.compare(b, a), greaterThan(0));
    });

    test('descending reverses order', () {
      final spec = SortSpec('salary', direction: SortDirection.descending);
      final a = {'salary': 72000};
      final b = {'salary': 95000};
      expect(spec.compare(a, b), greaterThan(0));
    });
  });

  // ── ProjectionSpec ────────────────────────────────────────────────────────

  group('ProjectionSpec', () {
    final record = {'id': '1', 'name': 'Alice', 'salary': 95000, 'ssn': '123'};

    test('include only specified fields', () {
      final proj = ProjectionSpec(includeFields: {'id', 'name'});
      final result = proj.apply(record);
      expect(result.keys, containsAll(['id', 'name']));
      expect(result.containsKey('salary'), isFalse);
    });

    test('exclude specified fields', () {
      final proj = ProjectionSpec(excludeFields: {'ssn', 'salary'});
      final result = proj.apply(record);
      expect(result.containsKey('ssn'), isFalse);
      expect(result.containsKey('salary'), isFalse);
      expect(result.containsKey('name'), isTrue);
    });

    test('empty projection returns full record', () {
      final proj = ProjectionSpec();
      expect(proj.apply(record), equals(record));
    });
  });

  // ── VaultQuery execution ──────────────────────────────────────────────────

  group('VaultQuery.execute', () {
    test('no predicates returns all records', () async {
      final result = await VaultQuery<Map<String, dynamic>>().execute(vault);
      expect(result.totalCount, equals(5));
    });

    test('where().equals() filters correctly', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Engineering')
          .execute(vault);
      expect(result.totalCount, equals(3));
    });

    test('AND chaining narrows results', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Engineering')
          .and('salary').greaterThan(90000)
          .execute(vault);
      expect(result.totalCount, equals(2)); // Alice + Diana
    });

    test('OR chaining broadens results', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Sales')
          .or('department').equals('HR')
          .execute(vault);
      expect(result.totalCount, equals(2));
    });

    test('orderBy sorts ascending', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Engineering')
          .orderBy('salary')
          .execute(vault);
      final salaries = result.records.map((r) => r['salary'] as int).toList();
      expect(salaries, equals([72000, 95000, 110000]));
    });

    test('orderByDesc sorts descending', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Engineering')
          .orderByDesc('salary')
          .execute(vault);
      final salaries = result.records.map((r) => r['salary'] as int).toList();
      expect(salaries, equals([110000, 95000, 72000]));
    });

    test('limit restricts result count', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .orderBy('salary')
          .limit(2)
          .execute(vault);
      expect(result.records.length, equals(2));
      expect(result.totalCount, equals(5));
      expect(result.hasMore, isTrue);
    });

    test('offset + limit implements pagination', () async {
      final page1 = await VaultQuery<Map<String, dynamic>>()
          .orderBy('salary').limit(2).offset(0).execute(vault);
      final page2 = await VaultQuery<Map<String, dynamic>>()
          .orderBy('salary').limit(2).offset(2).execute(vault);
      expect(page1.records.length, equals(2));
      expect(page2.records.length, equals(2));
      expect(page1.records[0], isNot(equals(page2.records[0])));
    });

    test('keyPrefix scans only matching keys', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .keyPrefix('emp:')
          .execute(vault);
      expect(result.totalCount, equals(5));
    });

    test('select projection applies correctly', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('department').equals('Sales')
          .select(['id', 'name'])
          .execute(vault);
      expect(result.records.length, equals(1));
      expect(result.records[0].containsKey('salary'), isFalse);
      expect(result.records[0].containsKey('name'), isTrue);
    });

    test('contains filter works case-insensitively', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('role').contains('senior')
          .execute(vault);
      expect(result.totalCount, equals(1)); // Alice
    });

    test('active field boolean filter', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .where('active').equals(false)
          .execute(vault);
      expect(result.totalCount, equals(1)); // Eve
    });

    test('QueryResult.hasMore is correct', () async {
      final result = await VaultQuery<Map<String, dynamic>>()
          .limit(3).offset(0).execute(vault);
      expect(result.hasMore, isTrue);
      expect(result.nextOffset, equals(3));
    });
  });
}
