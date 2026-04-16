# Compression Layer

> **Files**: `lib/src/compression/`
>
> - `compression_provider.dart` — Abstract interface
> - `gzip_provider.dart` — GZip (native or Lz4 fallback on web)
> - `lz4_provider.dart` — Pure-Dart Lz4 block codec
> - `deflate_provider.dart` — ZLib/Deflate (native or Lz4 fallback on web)
> - `auto_compression_provider.dart` — Auto-select by payload size (const version)
> - `auto_provider.dart` — Auto-select with `compressWithFlag()` helper
> - `no_compression_provider.dart` — Pass-through (no-op)
> - `compression_config.dart` — `CompressionStrategy` enum + `CompressionConfig`
> - `compression_factory.dart` — Factory: config → provider
> - `_io_codec_native.dart` — `dart:io` native GZip/ZLib functions
> - `_io_codec_stub.dart` — Web stubs (UnsupportedError)

---

## 1. `compression_provider.dart` — Abstract Interface

```dart
abstract class CompressionProvider {
  const CompressionProvider();

  /// Algorithm name used in statistics and audit logs.
  String get algorithmName;

  /// Integer flag written into the binary payload header.
  /// Must match a [CompressionFlag] constant.
  int get headerFlag;

  /// Compress [data]. Returns [data] unchanged if compression would
  /// increase size or if [data] is empty.
  Uint8List compress(Uint8List data);

  /// Decompress [compressedData].
  /// Throws [VaultDecompressionException] if corrupt or truncated.
  Uint8List decompress(Uint8List compressedData);

  /// Estimated compression ratio for [originalSize] bytes.
  /// Returns 0.0 (no savings) to 1.0 (perfect compression).
  double estimateRatio(int originalSize);

  /// Returns true if compression is worthwhile for [sizeBytes].
  bool isWorthCompressing(int sizeBytes) => estimateRatio(sizeBytes) > 0.05;
}
```

---

## 2. `gzip_provider.dart` — `GZipCompressionProvider`

```dart
class GZipCompressionProvider extends CompressionProvider {
  final int level;   // -1 (default≈6) to 9 (best ratio)
  const GZipCompressionProvider({this.level = 6});
}
```

### Platform Behaviour

| Platform | Backend | Notes |
|---|---|---|
| Android / iOS / Desktop | `dart:io GZipCodec` | Full GZip support |
| Flutter Web | `Lz4CompressionProvider` fallback | `dart:io` not available on web |

On web, `algorithmName` returns `'Lz4(web-fallback)'` and `headerFlag` returns `CompressionFlag.lz4`.

### Compression ratio estimates

| Data size | Estimated ratio |
|---|---|
| < 64 bytes | 0% (not compressed) |
| 64–255 bytes | ~20% |
| 256–1023 bytes | ~40% |
| 1024–16383 bytes | ~60% |
| ≥ 16384 bytes | ~70% |

### GZip magic detection

```dart
static bool hasGZipMagic(Uint8List data) =>
    !kIsWeb &&
    data.length >= 2 &&
    data[0] == 0x1f &&
    data[1] == 0x8b;
```

---

## 3. `lz4_provider.dart` — `Lz4CompressionProvider`

Pure-Dart implementation of the LZ4 block format. No native dependencies — works identically on all platforms including Flutter Web.

```dart
class Lz4CompressionProvider extends CompressionProvider {
  const Lz4CompressionProvider();
  String get algorithmName => 'Lz4';
  int get headerFlag => CompressionFlag.lz4;
}
```

### Performance Profile

| Metric | Value |
|---|---|
| Compression speed | 3–5× faster than GZip |
| Decompression speed | Very fast |
| Compression ratio | 40–65% on JSON |
| Native dependency | None (pure Dart) |
| Minimum block size | 4 bytes per match |

### Custom Frame Format

HiveVault uses its own mini-frame header instead of the official Lz4 frame format to embed `originalSize` for safe decompression:

```
Offset  Size     Field
──────  ───────  ─────────────────────────────────────
0       4 bytes  Magic: 0x48564C34 ('HVL4' — HiveVault Lz4)
4       4 bytes  Original (uncompressed) size (uint32 LE)
8       4 bytes  Compressed block size (uint32 LE)
12      N bytes  Lz4 block-format compressed data
```

### Magic detection

```dart
static bool hasLz4Magic(Uint8List data) {
  if (data.length < 4) return false;
  final v = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
  return v == 0x48564C34;
}
```

### Compression ratio estimates

| Data size | Estimated ratio |
|---|---|
| < 64 bytes | 0% |
| 64–511 bytes | ~20% |
| 512–4095 bytes | ~35% |
| 4096–65535 bytes | ~50% |
| ≥ 65536 bytes | ~58% |

### Internal Algorithm

The Lz4 block encoder uses:
- Hash table of 65536 slots for match finding
- Minimum match length: 4 bytes
- Back-reference offset: 2 bytes (max 65534 bytes lookback)
- Token format: `[literalLen:4bits | matchLen:4bits]` + variable-length extensions

---

## 4. `deflate_provider.dart` — `DeflateCompressionProvider`

ZLib/Deflate without the GZip header wrapping. Useful for interoperability with systems expecting raw Deflate streams.

```dart
class DeflateCompressionProvider extends CompressionProvider {
  final int level;   // -1..9
  const DeflateCompressionProvider({this.level = 6});
}
```

On Flutter Web falls back to Lz4 (same as `GZipCompressionProvider`).

**Ratios**: Virtually identical to GZip (same algorithm, different framing).

---

## 5. `auto_compression_provider.dart` — `AutoCompressionProvider` (const)

Size-adaptive selection. Designed to be a `const` instance (used via factory).

```dart
class AutoCompressionProvider extends CompressionProvider {
  static const int _tinyThreshold = 64;    // < 64 bytes: no compression
  final int largeThreshold;                 // default 4096 bytes

  // < tinyThreshold  → NoCompression
  // < largeThreshold → Lz4
  // ≥ largeThreshold → GZip
}
```

### Key Methods

```dart
// Returns the concrete provider that would be selected for a payload of [sizeBytes]
CompressionProvider selectFor(int sizeBytes);

// Returns the header flag for a payload of [sizeBytes]
int headerFlagFor(int sizeBytes);
```

### Decompress

Auto-decompression detects the algorithm by magic bytes:
1. Check for GZip magic (`0x1f 0x8b`) → delegate to GZipProvider
2. Check for HVL4 magic (`0x48564C34`) → delegate to Lz4Provider
3. Fallback → return data as-is (assumed uncompressed)

---

## 6. `auto_provider.dart` — `AutoCompressionProvider` (flag-aware)

An alternative auto-provider that exposes `compressWithFlag()` — returns both the compressed data and the correct header flag, which is necessary because the flag is set per-call rather than per-instance.

```dart
class AutoCompressionProvider extends CompressionProvider {
  // Same size thresholds as the const version

  AutoCompressResult compressWithFlag(Uint8List data);
  Uint8List decompressWithFlag(Uint8List data, int flag);
}

class AutoCompressResult {
  final Uint8List data;   // Compressed (or unchanged) bytes
  final int flag;         // CompressionFlag to store in payload header
}
```

Also provides `decompressWithFlag(data, flag)` for explicit dispatch when the flag is known from the payload header (which is the normal case during a read).

---

## 7. `no_compression_provider.dart` — `NoCompressionProvider`

```dart
class NoCompressionProvider extends CompressionProvider {
  const NoCompressionProvider();
  String get algorithmName => 'None';
  int get headerFlag => CompressionFlag.none;
  Uint8List compress(Uint8List data) => data;
  Uint8List decompress(Uint8List data) => data;
  double estimateRatio(int size) => 0.0;
  bool isWorthCompressing(int size) => false;
}
```

Use for:
- Already-compressed binary data (images, zip files, audio)
- Debug/test builds where storage readability matters
- Payloads that are known to not benefit from compression

---

## 8. `compression_factory.dart` — `CompressionFactory`

```dart
class CompressionFactory {
  static CompressionProvider create(CompressionConfig config) {
    switch (config.strategy) {
      case CompressionStrategy.none:    return const NoCompressionProvider();
      case CompressionStrategy.gzip:    return GZipCompressionProvider(level: config.gzipLevel);
      case CompressionStrategy.lz4:     return const Lz4CompressionProvider();
      case CompressionStrategy.deflate: return DeflateCompressionProvider(level: config.gzipLevel);
      case CompressionStrategy.auto:    return AutoCompressionProvider(
                                          gzipLevel: config.gzipLevel,
                                          minSize: config.minimumSizeForCompression,
                                        );
    }
  }
}
```

---

## 9. `_io_codec_native.dart` / `_io_codec_stub.dart`

Platform-conditional shims loaded via Dart's conditional import mechanism:

```dart
// In gzip_provider.dart / deflate_provider.dart:
import '_io_codec_stub.dart'
    if (dart.library.io) '_io_codec_native.dart';
```

| File | Platform | Implementation |
|---|---|---|
| `_io_codec_native.dart` | Non-web (uses `dart:io`) | Calls `GZipCodec` / `ZLibCodec` |
| `_io_codec_stub.dart` | Flutter Web | Throws `UnsupportedError` (never called in practice) |

The stubs exist to satisfy the Dart analyser and tree-shaker during web builds. On web, `kIsWeb` is checked first and the Lz4 fallback is used before any `dart:io` call is reached.

---

## Algorithm Selection Guide

```
Data type               Recommended strategy
─────────────────────   ──────────────────────────────────────
JSON / text             gzip (level 6) or auto
Binary (images, PDF)    none
Small objects (< 64 B)  none (automatic with auto/gzip)
Mixed workload          auto (adapts per payload)
Mobile / battery care   lz4 (faster, less CPU)
Maximum compression     gzip (level 9) or maxSecurity preset
Web-only app            lz4 (dart:io not available)
```

---

## Compression Ratio Comparison

For a typical ERP JSON record (~2 KB):

| Algorithm | Compressed size | Ratio | Compress speed |
|---|---|---|---|
| GZip-6 | ~900 bytes | 55% | Medium |
| GZip-9 | ~860 bytes | 57% | Slow |
| Lz4 | ~1100 bytes | 45% | Fast |
| Deflate-6 | ~895 bytes | 55% | Medium |
| None | 2048 bytes | 0% | Instant |
