# Background Processing Layer

> **Files**: `lib/src/background/`
>
> - `background_processor.dart` — Flutter `compute` offload for large payloads
> - `vault_counters.dart` — Mutable hit/miss/operation counters

---

## 1. `background_processor.dart` — `BackgroundProcessor`

Offloads CPU-bound compression and encryption operations to a separate Dart isolate using Flutter's `compute` function when payload size exceeds a configurable threshold.

```dart
class BackgroundProcessor {
  /// Byte threshold above which work is offloaded to a background isolate.
  final int threshold;

  BackgroundProcessor({this.threshold = kDefaultIsolateThreshold}); // 65536 = 64 KB
}
```

### Why Background Processing?

Encryption and compression are CPU-intensive. On the Flutter main isolate:
- GZip compression of a 1 MB payload: ~20–100 ms (device-dependent)
- AES-256-GCM encryption of a 1 MB payload: ~10–50 ms

This can cause visible frame drops (jank) on mobile. Payloads above the threshold are processed in a separate isolate to keep the UI responsive.

### `compress`

```dart
Future<Uint8List> compress(
  Uint8List data,
  CompressionProvider provider,
) async
```

- If `data.length < threshold`: runs `provider.compress(data)` on the calling isolate
- If `data.length >= threshold`: uses `compute(_compressInIsolate, message)` to offload

### `decompress`

```dart
Future<Uint8List> decompress(
  Uint8List data,
  CompressionProvider provider,
) async
```

Same threshold logic for decompression.

### Isolate Entry Points (top-level functions)

Because Dart isolates can only receive top-level functions, the work is dispatched via internal `_CompressMessage` / `_DecompressMessage` carrier classes:

```dart
class _CompressMessage {
  final Uint8List data;
  final CompressionProvider provider;
}

// Top-level function (not a class method):
Uint8List _compressInIsolate(_CompressMessage msg) {
  return msg.provider.compress(msg.data);
}

Uint8List _decompressInIsolate(_DecompressMessage msg) {
  return msg.provider.decompress(msg.data);
}
```

### Threshold Configuration

```dart
// Via VaultConfig:
VaultConfig(
  enableBackgroundProcessing: true,
  backgroundProcessingThreshold: 65536,  // 64 KB
)

// VaultConfig.light() disables background processing entirely:
VaultConfig.light()  // enableBackgroundProcessing: false
```

When `enableBackgroundProcessing` is `false`, all operations run synchronously on the main isolate regardless of payload size.

### Usage in HiveVaultImpl

```dart
// During secureSave:
final compressedData = config.enableBackgroundProcessing
    ? await _background.compress(rawBytes, _compression)
    : _compression.compress(rawBytes);

// During secureGet:
final decompressedData = config.enableBackgroundProcessing
    ? await _background.decompress(encryptedData, _compression)
    : _compression.decompress(encryptedData);
```

### Platform Notes

- **Flutter apps**: `compute` works on all platforms (Android, iOS, Web, Desktop)
- **Dart-only (no Flutter)**: Replace `compute` with `Isolate.run` from `dart:isolate`
- **Flutter Web**: `compute` uses Web Workers where available; on unsupported browsers it falls back to the main thread

---

## 2. `vault_counters.dart` — `VaultCounters`

Simple mutable counters used by `HiveVaultImpl` and exposed via the metrics/observability layer.

```dart
class VaultCounters {
  int cacheHits = 0;
  int cacheMisses = 0;
  int totalSaveOps = 0;
  int totalGetOps = 0;
  int totalDeleteOps = 0;
  int totalSearchOps = 0;
  int totalBatchSaveOps = 0;
  int totalBatchGetOps = 0;
  int totalBatchDeleteOps = 0;
  int totalErrors = 0;

  // Byte tracking
  int bytesWrittenRaw = 0;        // Pre-compression
  int bytesWrittenFinal = 0;      // Post-compression + post-encryption

  // Reset all counters to zero
  void reset();

  // Computed properties
  double get cacheHitRatio =>
      (cacheHits + cacheMisses) == 0
          ? 0.0
          : cacheHits / (cacheHits + cacheMisses);

  int get totalOps =>
      totalSaveOps + totalGetOps + totalDeleteOps + totalSearchOps;
}
```

### Relationship to `VaultStatsCounter`

`VaultCounters` (in `background/`) is a richer version of `VaultStatsCounter` (in `impl/`). They serve the same purpose but `VaultCounters` has additional per-operation-type counters and is used by the `VaultMetrics` observability layer.

`VaultStatsCounter` (the simpler one used directly in `HiveVaultImpl`) tracks:
- `totalWrites`, `totalReads`, `totalSearches`
- `totalOriginalBytesWritten`, `totalBytesWritten`, `totalBytesSaved`
- `openedAt` timestamp

---

## Background Processing Flow Diagram

```
secureSave(key, value)
        │
        ▼
  objectToBytes(value)     ← BinaryProcessor
        │
        ▼
  data.length >= threshold?
    YES → compute(_compressInIsolate)   ← BackgroundProcessor
    NO  → provider.compress(data)       ← in-line
        │
        ▼
  encryptionProvider.encrypt(compressed)
  (encryption runs on calling isolate — provider is async)
        │
        ▼
  createPayload(encrypted, flags)       ← BinaryProcessor
        │
        ▼
  box.put(key, payload)
```
