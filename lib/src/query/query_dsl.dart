// lib/src/query/query_dsl.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Advanced Query DSL (Domain-Specific Language).
//
// Provides a fluent, composable, type-safe API for building complex vault
// queries without writing raw search strings.
//
// Example:
//   final results = await Query<Employee>()
//       .where('department').equals('Engineering')
//       .and('salary').greaterThan(80000)
//       .or('role').contains('Senior')
//       .orderBy('name')
//       .limit(20)
//       .offset(0)
//       .execute(vault);
// ─────────────────────────────────────────────────────────────────────────────

import '../core/vault_interface.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Predicate types
// ═══════════════════════════════════════════════════════════════════════════

/// The logical combinator between two consecutive predicates.
enum PredicateCombinator { and, or }

/// Comparison operators available in the query DSL.
enum ComparisonOp {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains,
  startsWith,
  endsWith,
  isIn,
  isNotIn,
  isNull,
  isNotNull,
  between,
  regex,
}

/// A single filter predicate.
class QueryPredicate {
  final String field;
  final ComparisonOp op;
  final dynamic value;
  final dynamic value2; // used by [between]
  final PredicateCombinator combinator;

  const QueryPredicate({
    required this.field,
    required this.op,
    required this.combinator,
    this.value,
    this.value2,
  });

  /// Evaluates this predicate against a decoded [Map] record.
  bool evaluate(Map<String, dynamic> record) {
    // Field access supports dot-notation: 'address.city'
    final fieldValue = _getNestedField(record, field);

    switch (op) {
      case ComparisonOp.equals:
        return fieldValue == value;
      case ComparisonOp.notEquals:
        return fieldValue != value;
      case ComparisonOp.greaterThan:
        return _compareValues(fieldValue, value) > 0;
      case ComparisonOp.greaterThanOrEqual:
        return _compareValues(fieldValue, value) >= 0;
      case ComparisonOp.lessThan:
        return _compareValues(fieldValue, value) < 0;
      case ComparisonOp.lessThanOrEqual:
        return _compareValues(fieldValue, value) <= 0;
      case ComparisonOp.contains:
        return fieldValue
                ?.toString()
                .toLowerCase()
                .contains(value.toString().toLowerCase()) ??
            false;
      case ComparisonOp.startsWith:
        return fieldValue
                ?.toString()
                .toLowerCase()
                .startsWith(value.toString().toLowerCase()) ??
            false;
      case ComparisonOp.endsWith:
        return fieldValue
                ?.toString()
                .toLowerCase()
                .endsWith(value.toString().toLowerCase()) ??
            false;
      case ComparisonOp.isIn:
        final list = value as List;
        return list.contains(fieldValue);
      case ComparisonOp.isNotIn:
        final list = value as List;
        return !list.contains(fieldValue);
      case ComparisonOp.isNull:
        return fieldValue == null;
      case ComparisonOp.isNotNull:
        return fieldValue != null;
      case ComparisonOp.between:
        if (fieldValue == null) return false;
        return _compareValues(fieldValue, value) >= 0 &&
            _compareValues(fieldValue, value2) <= 0;
      case ComparisonOp.regex:
        final re = RegExp(value.toString(), caseSensitive: false);
        return re.hasMatch(fieldValue?.toString() ?? '');
    }
  }

  dynamic _getNestedField(Map<String, dynamic> record, String field) {
    final parts = field.split('.');
    dynamic current = record;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  @override
  String toString() =>
      '${combinator.name.toUpperCase()} $field ${op.name} $value';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sort specification
// ═══════════════════════════════════════════════════════════════════════════

/// Sort order direction.
enum SortDirection { ascending, descending }

/// A sort specification for a single field.
class SortSpec {
  final String field;
  final SortDirection direction;

  const SortSpec(this.field, {this.direction = SortDirection.ascending});

  int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aVal = _get(a, field);
    final bVal = _get(b, field);
    final cmp = _compareValues(aVal, bVal);
    return direction == SortDirection.ascending ? cmp : -cmp;
  }

  dynamic _get(Map<String, dynamic> record, String field) {
    final parts = field.split('.');
    dynamic current = record;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Projection specification
// ═══════════════════════════════════════════════════════════════════════════

/// Defines which fields to include or exclude from results.
class ProjectionSpec {
  final Set<String> includeFields;
  final Set<String> excludeFields;

  const ProjectionSpec({
    this.includeFields = const {},
    this.excludeFields = const {},
  });

  /// Applies the projection to [record], returning only the relevant fields.
  Map<String, dynamic> apply(Map<String, dynamic> record) {
    if (includeFields.isNotEmpty) {
      return {
        for (final f in includeFields)
          if (record.containsKey(f)) f: record[f],
      };
    }
    if (excludeFields.isNotEmpty) {
      return {
        for (final entry in record.entries)
          if (!excludeFields.contains(entry.key)) entry.key: entry.value,
      };
    }
    return record;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Fluent field builder
// ═══════════════════════════════════════════════════════════════════════════

/// Intermediate builder returned by [VaultQuery.where] / [VaultQuery.and] /
/// [VaultQuery.or]. Provides comparison operators for a specific [_field].
class FieldBuilder<T> {
  final String _field;
  final VaultQuery<T> _query;
  final PredicateCombinator _combinator;

  FieldBuilder(this._field, this._query, this._combinator);

  VaultQuery<T> equals(dynamic value) =>
      _addPredicate(ComparisonOp.equals, value);
  VaultQuery<T> notEquals(dynamic value) =>
      _addPredicate(ComparisonOp.notEquals, value);
  VaultQuery<T> greaterThan(dynamic value) =>
      _addPredicate(ComparisonOp.greaterThan, value);
  VaultQuery<T> greaterThanOrEqual(dynamic value) =>
      _addPredicate(ComparisonOp.greaterThanOrEqual, value);
  VaultQuery<T> lessThan(dynamic value) =>
      _addPredicate(ComparisonOp.lessThan, value);
  VaultQuery<T> lessThanOrEqual(dynamic value) =>
      _addPredicate(ComparisonOp.lessThanOrEqual, value);
  VaultQuery<T> contains(String value) =>
      _addPredicate(ComparisonOp.contains, value);
  VaultQuery<T> startsWith(String value) =>
      _addPredicate(ComparisonOp.startsWith, value);
  VaultQuery<T> endsWith(String value) =>
      _addPredicate(ComparisonOp.endsWith, value);
  VaultQuery<T> isIn(List<dynamic> values) =>
      _addPredicate(ComparisonOp.isIn, values);
  VaultQuery<T> isNotIn(List<dynamic> values) =>
      _addPredicate(ComparisonOp.isNotIn, values);
  VaultQuery<T> isNull() => _addPredicate(ComparisonOp.isNull, null);
  VaultQuery<T> isNotNull() => _addPredicate(ComparisonOp.isNotNull, null);
  VaultQuery<T> between(dynamic lower, dynamic upper) =>
      _addPredicateBetween(lower, upper);
  VaultQuery<T> matchesRegex(String pattern) =>
      _addPredicate(ComparisonOp.regex, pattern);

  VaultQuery<T> _addPredicate(ComparisonOp op, dynamic value) {
    _query._predicates.add(QueryPredicate(
      field: _field,
      op: op,
      value: value,
      combinator: _combinator,
    ));
    return _query;
  }

  VaultQuery<T> _addPredicateBetween(dynamic lower, dynamic upper) {
    _query._predicates.add(QueryPredicate(
      field: _field,
      op: ComparisonOp.between,
      value: lower,
      value2: upper,
      combinator: _combinator,
    ));
    return _query;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Query result
// ═══════════════════════════════════════════════════════════════════════════

/// The result of a vault query execution.
class QueryResult<T> {
  /// The matching records, after sorting, projection, and pagination.
  final List<T> records;

  /// The matching keys in the same order as [records].
  final List<String> keys;

  /// Total number of matches before pagination.
  final int totalCount;

  /// The offset used for this page.
  final int offset;

  /// The limit used for this page.
  final int? limit;

  const QueryResult({
    required this.records,
    required this.keys,
    required this.totalCount,
    required this.offset,
    this.limit,
  });

  bool get hasMore => limit != null && (offset + records.length) < totalCount;

  int get nextOffset => offset + records.length;

  @override
  String toString() =>
      'QueryResult(count: ${records.length}, total: $totalCount, '
      'offset: $offset, hasMore: $hasMore)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main VaultQuery builder
// ═══════════════════════════════════════════════════════════════════════════

/// Fluent query builder for HiveVault.
///
/// Supports filtering, sorting, pagination, projection, and both AND/OR logic.
///
/// Usage:
/// ```dart
/// final result = await VaultQuery<Map<String, dynamic>>()
///     .where('status').equals('active')
///     .and('age').greaterThan(18)
///     .orderBy('name')
///     .limit(10)
///     .execute(vault);
/// ```
class VaultQuery<T> {
  final List<QueryPredicate> _predicates = [];
  final List<SortSpec> _sorts = [];
  int _offset = 0;
  int? _limit;
  ProjectionSpec? _projection;
  String? _keyPrefix;

  // ── Filter builders ──────────────────────────────────────────────────────

  /// Begins a predicate chain with AND logic for [field].
  FieldBuilder<T> where(String field) =>
      FieldBuilder(field, this, PredicateCombinator.and);

  /// Appends an AND predicate for [field].
  FieldBuilder<T> and(String field) =>
      FieldBuilder(field, this, PredicateCombinator.and);

  /// Appends an OR predicate for [field].
  FieldBuilder<T> or(String field) =>
      FieldBuilder(field, this, PredicateCombinator.or);

  // ── Sorting ──────────────────────────────────────────────────────────────

  /// Sorts results ascending by [field].
  VaultQuery<T> orderBy(String field) {
    _sorts.add(SortSpec(field, direction: SortDirection.ascending));
    return this;
  }

  /// Sorts results descending by [field].
  VaultQuery<T> orderByDesc(String field) {
    _sorts.add(SortSpec(field, direction: SortDirection.descending));
    return this;
  }

  /// Adds a secondary (tiebreaker) sort on [field].
  VaultQuery<T> thenBy(String field) => orderBy(field);
  VaultQuery<T> thenByDesc(String field) => orderByDesc(field);

  // ── Pagination ───────────────────────────────────────────────────────────

  /// Limits the number of results returned.
  VaultQuery<T> limit(int n) {
    assert(n > 0, 'limit must be positive');
    _limit = n;
    return this;
  }

  /// Skips the first [n] matching results.
  VaultQuery<T> offset(int n) {
    assert(n >= 0, 'offset must be non-negative');
    _offset = n;
    return this;
  }

  // ── Projection ───────────────────────────────────────────────────────────

  /// Only include these fields in each returned record.
  VaultQuery<T> select(List<String> fields) {
    _projection = ProjectionSpec(includeFields: Set.from(fields));
    return this;
  }

  /// Exclude these fields from each returned record.
  VaultQuery<T> exclude(List<String> fields) {
    _projection = ProjectionSpec(excludeFields: Set.from(fields));
    return this;
  }

  // ── Key filter ───────────────────────────────────────────────────────────

  /// Only scan keys that start with [prefix].
  VaultQuery<T> keyPrefix(String prefix) {
    _keyPrefix = prefix;
    return this;
  }

  // ── Execution ────────────────────────────────────────────────────────────

  /// Executes this query against [vault] and returns a [QueryResult].
  ///
  /// All entries are loaded and filtered in-memory.
  /// For large vaults, use [keyPrefix] or TTL-based eviction to reduce scan scope.
  Future<QueryResult<T>> execute(SecureStorageInterface vault) async {
    // 1 — Determine candidate keys.
    final allKeys = await vault.getAllKeys();
    final candidateKeys = _keyPrefix != null
        ? allKeys.where((k) => k.startsWith(_keyPrefix!)).toList()
        : allKeys;

    // 2 — Load, filter, and collect matches.
    final matches = <_KeyedRecord<T>>[];
    for (final key in candidateKeys) {
      final raw = await vault.secureGet<dynamic>(key);
      if (raw == null) continue;

      final record =
          raw is Map<String, dynamic> ? raw : <String, dynamic>{'__value': raw};

      if (_matchesPredicates(record)) {
        // Apply projection.
        final projected =
            _projection != null ? _projection!.apply(record) : record;

        matches.add(_KeyedRecord<T>(key, projected as T, record));
      }
    }

    final totalCount = matches.length;

    // 3 — Sort.
    if (_sorts.isNotEmpty) {
      matches.sort((a, b) {
        for (final sort in _sorts) {
          final cmp = sort.compare(a.raw, b.raw);
          if (cmp != 0) return cmp;
        }
        return 0;
      });
    }

    // 4 — Paginate.
    final paginated = _limit != null
        ? matches.skip(_offset).take(_limit!).toList()
        : matches.skip(_offset).toList();

    return QueryResult<T>(
      records: paginated.map((m) => m.value).toList(),
      keys: paginated.map((m) => m.key).toList(),
      totalCount: totalCount,
      offset: _offset,
      limit: _limit,
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  bool _matchesPredicates(Map<String, dynamic> record) {
    if (_predicates.isEmpty) return true;

    bool result = _predicates.first.evaluate(record);
    for (int i = 1; i < _predicates.length; i++) {
      final pred = _predicates[i];
      if (pred.combinator == PredicateCombinator.and) {
        result = result && pred.evaluate(record);
      } else {
        result = result || pred.evaluate(record);
      }
    }
    return result;
  }
}

/// Internal holder that keeps both the projected (user-visible) value and the
/// raw (full) record needed for sorting.
class _KeyedRecord<T> {
  final String key;
  final T value;
  final Map<String, dynamic> raw;

  _KeyedRecord(this.key, this.value, this.raw);
}
