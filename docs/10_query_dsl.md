# Query DSL

> **File**: `lib/src/query/query_dsl.dart`

The HiveVault Query DSL provides a fluent, type-safe predicate builder for filtering, sorting, and paginating vault records without writing raw loops.

---

## Core Types

### `ComparisonOp` — Comparison Operators

```dart
enum ComparisonOp {
  equals, notEquals,
  greaterThan, greaterThanOrEqual,
  lessThan, lessThanOrEqual,
  contains, startsWith, endsWith,
  isIn, isNotIn,
  isNull, isNotNull,
  between,
  regex,
}
```

### `PredicateCombinator`

```dart
enum PredicateCombinator { and, or }
```

### `SortDirection`

```dart
enum SortDirection { ascending, descending }
```

---

## `QueryPredicate`

Represents a single filter condition.

```dart
class QueryPredicate {
  final String field;                // Dot-notation field path: "address.city"
  final ComparisonOp op;
  final dynamic value;               // Primary comparison value
  final dynamic value2;              // Second value for 'between'
  final PredicateCombinator combinator;  // How to combine with next predicate

  /// Evaluates this predicate against a [record] map.
  bool evaluate(Map<String, dynamic> record);
}
```

### Nested Field Access

The `evaluate` method supports dot-notation for nested maps:

```dart
// Field: "address.city"
// Record: {"address": {"city": "London", "zip": "EC1A"}}
// → evaluates against "London"
```

### Supported Operators in `evaluate`

| Op | Dart check |
|---|---|
| `equals` | `fieldValue == value` |
| `notEquals` | `fieldValue != value` |
| `greaterThan` | `(fieldValue as Comparable).compareTo(value) > 0` |
| `greaterThanOrEqual` | `compareTo >= 0` |
| `lessThan` | `compareTo < 0` |
| `lessThanOrEqual` | `compareTo <= 0` |
| `contains` | `fieldValue.toString().contains(value.toString())` |
| `startsWith` | `fieldValue.toString().startsWith(value.toString())` |
| `endsWith` | `fieldValue.toString().endsWith(value.toString())` |
| `isIn` | `(value as List).contains(fieldValue)` |
| `isNotIn` | `!(value as List).contains(fieldValue)` |
| `isNull` | `fieldValue == null` |
| `isNotNull` | `fieldValue != null` |
| `between` | `value <= fieldValue <= value2` |
| `regex` | `RegExp(value.toString()).hasMatch(fieldValue.toString())` |

---

## `FieldBuilder<T>`

Provides a chainable API to construct predicates for a specific field.

```dart
class FieldBuilder<T> {
  FieldBuilder(this._fieldName, this._query);

  // Equality
  VaultQuery<T> equals(dynamic value);
  VaultQuery<T> notEquals(dynamic value);

  // Numeric comparison
  VaultQuery<T> greaterThan(dynamic value);
  VaultQuery<T> greaterThanOrEqual(dynamic value);
  VaultQuery<T> lessThan(dynamic value);
  VaultQuery<T> lessThanOrEqual(dynamic value);

  // String checks
  VaultQuery<T> contains(dynamic value);
  VaultQuery<T> startsWith(dynamic value);
  VaultQuery<T> endsWith(dynamic value);

  // Collection membership
  VaultQuery<T> isIn(List<dynamic> values);
  VaultQuery<T> isNotIn(List<dynamic> values);

  // Null checks
  VaultQuery<T> isNull();
  VaultQuery<T> isNotNull();

  // Range
  VaultQuery<T> between(dynamic lower, dynamic upper);

  // Regex
  VaultQuery<T> matchesRegex(String pattern);
}
```

---

## `VaultQuery<T>`

The main query builder class.

```dart
class VaultQuery<T> {
  final List<QueryPredicate> _predicates = [];
  final List<SortSpec> _sorts = [];
  int? _limit;
  int? _offset;
  ProjectionSpec? _projection;
  String? _keyPrefix;
}
```

### Building a Query

```dart
// Convenience entry point
VaultQuery<Map<String, dynamic>> query = VaultQuery<Map<String, dynamic>>();
```

### Predicate Methods

```dart
// WHERE (AND by default)
query.where('status').equals('active');
query.and('balance').greaterThan(1000);
query.or('category').equals('premium');

// Chained:
final query = VaultQuery<Map>()
    .where('status').equals('active')
    .and('balance').greaterThanOrEqual(500)
    .and('region').isIn(['US', 'EU', 'APAC']);
```

### Sorting

```dart
query.orderBy('name');                      // Ascending
query.orderByDesc('balance');               // Descending
query.orderBy('region').thenBy('name');     // Multi-level sort
query.orderByDesc('createdAt').thenByDesc('balance');
```

### Pagination

```dart
query.limit(20).offset(40);   // Page 3 of 20 records/page
```

### Projection

```dart
// Include only specific fields
query.select(['name', 'email', 'balance']);

// Exclude specific fields
query.exclude(['password', 'internalNotes']);
```

### Key Prefix Filter

```dart
// Only query keys starting with a prefix (performance optimization)
query.keyPrefix('CLI-');
// Reduces the key scan from all keys to just CLI-* keys
```

---

## `QueryResult<T>`

```dart
class QueryResult<T> {
  final List<T> records;      // Matched records (projected)
  final List<String> keys;    // Corresponding vault keys
  final int totalCount;       // Total matching records before pagination
  final int offset;
  final int? limit;

  bool get hasMore => limit != null && offset + records.length < totalCount;
  int? get nextOffset => hasMore ? offset + records.length : null;
}
```

---

## `execute(vault)` — Query Execution

```dart
Future<QueryResult<T>> execute(SecureStorageInterface vault) async
```

Execution pipeline:

```
1. Determine keys to scan:
   - If keyPrefix set: getAllKeys() → filter by prefix
   - Otherwise: getAllKeys()

2. Load records:
   - For each key: vault.secureGet<T>(key)
   - Skip null (missing) results

3. Filter:
   - Apply predicates in order with AND/OR combinators
   - Only records where all AND predicates pass (and any OR predicates)

4. Count totalCount (before pagination)

5. Apply projection (include/exclude fields)

6. Sort by SortSpec list (stable multi-level sort)

7. Apply offset + limit

8. Return QueryResult
```

---

## Full Example

```dart
// Find all active clients in Europe with balance > $5000,
// sorted by balance descending, page 2 (20 per page)

final result = await VaultQuery<Map<String, dynamic>>()
    .where('status').equals('active')
    .and('region').equals('Europe')
    .and('balance').greaterThan(5000)
    .orderByDesc('balance')
    .thenBy('name')
    .limit(20)
    .offset(20)                      // page 2
    .select(['id', 'name', 'email', 'balance', 'region'])
    .keyPrefix('CLI-')               // Only scan client keys
    .execute(vault);

print('Total matches: ${result.totalCount}');
print('This page: ${result.records.length}');
print('Has more: ${result.hasMore}');

for (final client in result.records) {
  print('${client['name']}: \$${client['balance']}');
}
```

---

## `SortSpec`

```dart
class SortSpec {
  final String field;
  final SortDirection direction;
}
```

Multi-level sorting is performed as a stable sort — primary sort field first, then secondary fields applied within equal primary values.

---

## `ProjectionSpec`

```dart
class ProjectionSpec {
  final Set<String> includeFields;  // When non-empty: whitelist
  final Set<String> excludeFields;  // When non-empty: blacklist

  Map<String, dynamic> apply(Map<String, dynamic> record);
}
```

If both `includeFields` and `excludeFields` are set, `includeFields` takes precedence.
