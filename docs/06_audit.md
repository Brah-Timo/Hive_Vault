# Audit Layer

> **Files**: `lib/src/audit/`
>
> - `audit_entry.dart` — `AuditAction` enum + `AuditEntry` model
> - `audit_logger.dart` — Bounded in-memory ring-buffer audit log

---

## 1. `audit_entry.dart`

### `AuditAction` Enum

Enumerates every operation type that can be audited:

```dart
enum AuditAction {
  save,         // secureSave (single)
  get,          // secureGet (single)
  delete,       // secureDelete (single)
  search,       // secureSearch / secureSearchAny / secureSearchPrefix
  batchSave,    // secureSaveBatch
  batchGet,     // secureGetBatch
  batchDelete,  // secureDeleteBatch
  rebuildIndex, // rebuildIndex()
  compact,      // compact()
  exportData,   // exportEncrypted()
  importData,   // importEncrypted()
  keyRotation,  // key rotation event
  cacheHit,     // LRU cache hit on secureGet
  cacheMiss,    // LRU cache miss on secureGet
  error,        // Any caught exception
}
```

### `AuditEntry` Class

```dart
@immutable
class AuditEntry {
  final DateTime timestamp;
  final AuditAction action;
  final String key;              // Vault key (or query string for search)
  final int? originalSize;       // Pre-compression bytes
  final int? compressedSize;     // After compression
  final int? encryptedSize;      // After encryption (final stored size)
  final bool fromCache;          // true for cacheHit
  final Duration elapsed;        // Wall-clock time for the operation
  final String? details;         // Additional context (e.g., error message)
}
```

### Computed Properties

```dart
/// Compression ratio: 1.0 - (compressedSize / originalSize)
double? get compressionRatio;

/// Human-readable: e.g., "42.3%"
String? get compressionRatioLabel;

/// Human-readable elapsed: e.g., "1.23ms", "450μs"
String get elapsedLabel;
```

### Serialization

```dart
Map<String, dynamic> toMap() => {
  'timestamp': timestamp.toIso8601String(),
  'action': action.name,
  'key': key,
  'originalSize': originalSize,
  'compressedSize': compressedSize,
  'encryptedSize': encryptedSize,
  'fromCache': fromCache,
  'elapsedMs': elapsed.inMicroseconds / 1000.0,
  'details': details,
};
```

### Example Audit Entry

```
2024-03-15T14:32:05.123Z  save  PROD-001
  originalSize: 1,024 bytes
  compressedSize: 412 bytes (ratio: 59.8%)
  encryptedSize: 444 bytes
  fromCache: false
  elapsed: 2.34 ms
```

---

## 2. `audit_logger.dart` — `AuditLogger`

An in-memory ring buffer that retains the most recent N audit entries.

### Constructor

```dart
AuditLogger({int maxEntries = 1000});
```

### Recording Entries

```dart
// Low-level: add a pre-built AuditEntry
void record(AuditEntry entry);

// High-level: build and record in one call
void log({
  required AuditAction action,
  required String key,
  int? originalSize,
  int? compressedSize,
  int? encryptedSize,
  bool fromCache = false,
  required Duration elapsed,
  String? details,
});
```

### Querying the Log

```dart
// Number of entries currently stored
int get length;
bool get isEmpty;

// Most recent N entries (newest first)
List<AuditEntry> getRecent(int count);

// All entries for a specific key
List<AuditEntry> getByKey(String key);

// All entries for a specific action type
List<AuditEntry> getByAction(AuditAction action);

// Entries within a date range
List<AuditEntry> getByTimeRange(DateTime start, DateTime end);

// All error entries
List<AuditEntry> getErrors();
```

### Summary Statistics

```dart
Map<String, dynamic> getSummary() => {
  'totalEntries': ...,
  'actionCounts': {
    'save': 1247,
    'get': 8932,
    'search': 83,
    'cacheHit': 7421,
    'cacheMiss': 1511,
    // ...
  },
  'totalOriginalBytes': 52428800,
  'totalCompressedBytes': 21299200,
  'compressionRatio': 0.594,    // 59.4% saved
  'cacheHits': 7421,
  'cacheMisses': 1511,
  'cacheHitRatio': 0.831,       // 83.1% cache hit rate
  'totalElapsedMs': 3241.7,
};
```

### Export

```dart
// Export as JSON bytes (UTF-8 encoded)
Uint8List json = logger.exportJson();
// [{"timestamp":"...","action":"save","key":"PROD-001",...}, ...]
```

### Formatted Report

```dart
String report = logger.formatReport(count: 20);
// ═══════════════════════════════════
//   HiveVault Audit Report
//   Last 20 entries
// ═══════════════════════════════════
//   2024-03-15 14:32:05  save  PROD-001  2.3ms  (59.8% comp)
//   2024-03-15 14:32:04  get   CLI-007   0.1ms  [cache]
//   ...
// ───────────────────────────────────
//   Cache hit ratio: 83.1%
//   Avg compression: 59.4%
```

### Clearing

```dart
logger.clear();  // Empties the ring buffer and resets all counters
```

---

## Audit Integration in HiveVaultImpl

Every major operation in `HiveVaultImpl` records to the `AuditLogger`:

```dart
// On secureSave:
_audit.log(
  action: AuditAction.save,
  key: key,
  originalSize: originalBytes,
  compressedSize: compressedBytes,
  encryptedSize: finalBytes,
  elapsed: stopwatch.elapsed,
);

// On cache hit:
_audit.log(
  action: AuditAction.cacheHit,
  key: key,
  fromCache: true,
  elapsed: Duration.zero,
);

// On error:
_audit.log(
  action: AuditAction.error,
  key: key,
  elapsed: stopwatch.elapsed,
  details: e.toString(),
);
```

### Retrieving the Audit Log

```dart
// Via SecureStorageInterface (top-level API)
List<AuditEntry> recent = vault.getAuditLog(limit: 50);

// Via HiveVaultImpl directly
List<AuditEntry> errors = impl.auditLogger.getErrors();
Map<String, dynamic> summary = impl.auditLogger.getSummary();
```

---

## Audit Log Configuration

Audit logging is controlled by `VaultConfig.enableAuditLog`:

```dart
// Enable (default):
VaultConfig(enableAuditLog: true)

// Disable (e.g., maxPerformance preset):
VaultConfig(enableAuditLog: false)
// → AuditLogger is still created but log() calls are no-ops

// Adjust ring buffer size:
// (set via HiveVaultImpl constructor — not exposed in VaultConfig directly)
AuditLogger(maxEntries: 5000)
```

---

## Common Audit Patterns

### Monitor cache effectiveness

```dart
final summary = vault.getAuditLog(limit: 1000);
final hits = entries.where((e) => e.action == AuditAction.cacheHit).length;
final misses = entries.where((e) => e.action == AuditAction.cacheMiss).length;
print('Cache hit rate: ${hits / (hits + misses) * 100:.1f}%');
```

### Find slow operations

```dart
final slow = vault.getAuditLog(limit: 1000)
    .where((e) => e.elapsed.inMilliseconds > 50)
    .toList()
  ..sort((a, b) => b.elapsed.compareTo(a.elapsed));
```

### Detect errors

```dart
final errors = impl.auditLogger.getErrors();
for (final err in errors) {
  print('${err.timestamp}: ${err.key} — ${err.details}');
}
```
