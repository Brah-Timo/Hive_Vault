# Observability Layer

> **File**: `lib/src/observability/vault_metrics.dart`

`VaultMetrics` provides Prometheus-style counters and gauges for monitoring vault health in production environments.

---

## `VaultMetrics`

A centralized metrics collector that can be embedded in an existing observability stack (Prometheus, Datadog, OpenTelemetry, etc.).

```dart
class VaultMetrics {
  final String vaultName;

  VaultMetrics({required this.vaultName});
}
```

### Counters (monotonically increasing)

```dart
int get totalWrites;
int get totalReads;
int get totalSearches;
int get totalDeletes;
int get totalErrors;
int get totalCacheHits;
int get totalCacheMisses;
int get totalBytesWrittenRaw;       // Pre-compression bytes
int get totalBytesWrittenCompressed;// Post-compression bytes
int get totalKeyRotations;
```

### Gauges (current value at a point in time)

```dart
int get currentEntryCount;
int get currentCacheSize;
double get currentCacheHitRatio;    // 0.0 – 1.0
double get currentCompressionRatio; // 0.0 – 1.0
Duration get uptime;
```

### Recording Operations

```dart
void recordWrite({
  required int rawBytes,
  required int compressedBytes,
});

void recordRead({bool fromCache = false});

void recordSearch();

void recordDelete();

void recordError(String context, Object error);

void recordKeyRotation();

void updateEntryCount(int count);
void updateCacheSize(int size);
```

### Snapshot

```dart
Map<String, dynamic> snapshot() => {
  'vault': vaultName,
  'timestamp': DateTime.now().toIso8601String(),
  'writes': totalWrites,
  'reads': totalReads,
  'searches': totalSearches,
  'deletes': totalDeletes,
  'errors': totalErrors,
  'cache_hits': totalCacheHits,
  'cache_misses': totalCacheMisses,
  'cache_hit_ratio': currentCacheHitRatio,
  'bytes_written_raw': totalBytesWrittenRaw,
  'bytes_written_compressed': totalBytesWrittenCompressed,
  'compression_ratio': currentCompressionRatio,
  'entry_count': currentEntryCount,
  'cache_size': currentCacheSize,
  'uptime_seconds': uptime.inSeconds,
};
```

### Prometheus Export

```dart
String toPrometheusFormat() {
  // Returns multi-line Prometheus text exposition format:
  // # HELP hive_vault_writes_total Total number of write operations
  // # TYPE hive_vault_writes_total counter
  // hive_vault_writes_total{vault="products"} 3481
  // ...
}
```

### Reset

```dart
void reset();  // Resets all counters to zero (useful for testing)
```

---

## Integration with HiveVaultImpl

`VaultMetrics` is designed to be injected into `HiveVaultImpl`:

```dart
final metrics = VaultMetrics(vaultName: 'products');

// After creating the vault:
// (HiveVaultImpl exposes an optional metrics callback)

// Manual recording:
metrics.recordWrite(rawBytes: 1024, compressedBytes: 400);
metrics.recordRead(fromCache: false);
metrics.recordSearch();
```

---

## Observability Integration Examples

### Prometheus / Grafana

```dart
// Expose metrics endpoint in your Flutter app or server
final metricsEndpoint = ShelfMetricsHandler(vaultMetrics);
// GET /metrics → toPrometheusFormat()
```

### Logging

```dart
Timer.periodic(Duration(minutes: 5), (_) {
  final snap = metrics.snapshot();
  logger.info('VaultMetrics', snap);
});
```

### Alerting Thresholds

```dart
if (metrics.currentCacheHitRatio < 0.5) {
  alerting.warn('Low vault cache hit ratio: ${metrics.currentCacheHitRatio}');
}
if (metrics.totalErrors > 100) {
  alerting.error('High vault error count: ${metrics.totalErrors}');
}
```

---

## Relationship to `VaultStats` and `AuditLogger`

| Component | Storage | Granularity | Purpose |
|---|---|---|---|
| `VaultStats` | Snapshot (immutable) | Aggregate | One-time diagnostics |
| `AuditLogger` | Ring buffer (1000 entries) | Per-operation | Debugging recent activity |
| `VaultMetrics` | Live counters | Aggregate | Production monitoring |

Use `VaultStats` for `getStats()` → one-time health view.
Use `AuditLogger` for recent operation history and debugging.
Use `VaultMetrics` for long-running production monitoring and alerting.
