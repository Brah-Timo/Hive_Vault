# Vault Health Checker

> **File**: `lib/src/impl/vault_health.dart`

Automated diagnostics that analyze vault runtime statistics and produce structured health reports.

---

## `HealthSeverity`

```dart
enum HealthSeverity { info, warning, error, critical }
```

| Level | Meaning |
|---|---|
| `info` | Informational — vault is healthy on this dimension |
| `warning` | Something could be improved but vault is functional |
| `error` | A problem that may impact correctness or performance |
| `critical` | A severe problem that requires immediate action |

---

## `HealthIssue`

```dart
@immutable
class HealthIssue {
  final HealthSeverity severity;
  final String code;                // Machine-readable identifier
  final String message;             // Human-readable description
  final String? recommendation;     // Suggested fix

  @override
  String toString() => '[${severity.name.toUpperCase()}] $code: $message\n  → $recommendation';
}
```

---

## `HealthReport`

```dart
@immutable
class HealthReport {
  final DateTime checkedAt;
  final List<HealthIssue> issues;
  final VaultStats stats;

  bool get isHealthy   => issues.every((i) => i.severity == HealthSeverity.info);
  bool get hasCritical => issues.any((i) => i.severity == HealthSeverity.critical);

  List<HealthIssue> get errors   => issues.where(severity == error).toList();
  List<HealthIssue> get warnings => issues.where(severity == warning).toList();
}
```

The `toString()` method formats a full report:

```
═════════════════════════════════════════════
  HiveVault Health Report
  Checked at: 2024-03-15T14:32:05.000Z
  Status: ⚠️ Issues found
═════════════════════════════════════════════
  [WARNING] LOW_CACHE_HIT_RATIO: Cache hit ratio is 42.3% (threshold: 50%)
    → Consider increasing memoryCacheSize in VaultConfig.
  [INFO] CACHE_OK: (not shown — only warnings/errors)
─────────────────────────────────────────────
  [VaultStats output follows...]
```

---

## `VaultHealthChecker`

```dart
class VaultHealthChecker {
  static Future<HealthReport> check(SecureStorageInterface vault) async;
}
```

A static utility — no instantiation required.

### Usage

```dart
final report = await VaultHealthChecker.check(vault);

if (!report.isHealthy) {
  for (final issue in report.issues) {
    print(issue);
  }
}

if (report.hasCritical) {
  // Take emergency action
  await vault.compact();
  await vault.rebuildIndex();
}
```

---

## Checks Performed

### 1. Cache Health

**Code**: `LOW_CACHE_HIT_RATIO` / `CACHE_OK`

```dart
// Threshold: 50% hit ratio after > 100 reads
if (stats.cacheCapacity > 0 && stats.totalReads > 100) {
  if (stats.cacheHitRatio < 0.5) {
    → WARNING: LOW_CACHE_HIT_RATIO
      message: "Cache hit ratio is 42.3% (threshold: 50%)"
      recommendation: "Consider increasing memoryCacheSize in VaultConfig."
  } else {
    → INFO: CACHE_OK
  }
}
```

### 2. Index Size

**Code**: `LARGE_INDEX`

```dart
// Threshold: 100,000 indexed entries
if (stats.indexStats.totalEntries > 100000) {
  → WARNING: LARGE_INDEX
    message: "Index contains 142,000 entries (memory: 8.4 MB)"
    recommendation: "Consider using indexableFields to limit indexed fields."
}
```

### 3. Compression Effectiveness

**Code**: `LOW_COMPRESSION_RATIO`

```dart
// Threshold: < 10% savings after > 50 writes (and compression is enabled)
if (stats.totalWrites > 50 && compressionAlgorithm != 'None') {
  if (stats.compressionRatio < 0.10) {
    → WARNING: LOW_COMPRESSION_RATIO
      message: "Compression ratio is 3.2% — compression may not be beneficial."
      recommendation: "Consider CompressionStrategy.none or increasing minimumSizeForCompression."
  }
}
```

### 4. Empty Vault After Writes

**Code**: `EMPTY_VAULT`

```dart
if (stats.totalEntries == 0 && stats.totalWrites > 0) {
  → WARNING: EMPTY_VAULT
    message: "Vault appears empty despite recorded writes."
}
```

### 5. Partial Index Coverage

**Code**: `PARTIAL_INDEX`

```dart
if (totalEntries > 0 && indexedEntries < totalEntries * 0.5) {
  → INFO: PARTIAL_INDEX
    message: "Only 45/100 entries are indexed."
    recommendation: "Call rebuildIndex() or provide searchableText on save."
}
```

---

## Scheduled Health Checks

```dart
// Check health every hour
Timer.periodic(Duration(hours: 1), (_) async {
  final report = await VaultHealthChecker.check(vault);
  if (!report.isHealthy) {
    logger.warn('Vault health issues detected', {
      'issues': report.issues.map((i) => i.code).toList(),
    });
  }
});
```

---

## Issue Code Reference

| Code | Severity | Trigger |
|---|---|---|
| `CACHE_OK` | info | Cache hit ratio ≥ 50% |
| `LOW_CACHE_HIT_RATIO` | warning | Cache hit ratio < 50% (after 100 reads) |
| `LARGE_INDEX` | warning | Index > 100,000 entries |
| `LOW_COMPRESSION_RATIO` | warning | Compression saves < 10% (after 50 writes) |
| `EMPTY_VAULT` | warning | No entries despite writes |
| `PARTIAL_INDEX` | info | < 50% of entries are indexed |
