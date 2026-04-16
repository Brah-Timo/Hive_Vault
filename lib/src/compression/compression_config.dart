// lib/src/compression/compression_config.dart

import 'package:meta/meta.dart';

/// Which compression algorithm the vault should use.
enum CompressionStrategy {
  /// No compression — data is stored as-is.
  none,

  /// GZip (deflate + header) — best ratio for text/JSON, moderate speed.
  gzip,

  /// LZ4 — fastest compression with reasonable ratio.
  lz4,

  /// Deflate (raw, no GZip header) — useful when interoperability matters.
  deflate,

  /// Auto-select based on payload size:
  ///   < isolateThreshold → Lz4  |  ≥ isolateThreshold → GZip
  auto,
}

/// Compression settings carried inside [VaultConfig].
@immutable
class CompressionConfig {
  const CompressionConfig({
    this.strategy = CompressionStrategy.gzip,
    this.minimumSizeForCompression = 64,
    this.gzipLevel = 6,
    this.useIsolateForLargeData = true,
    this.isolateThreshold = 65536,
  });

  /// Compression algorithm to apply.
  final CompressionStrategy strategy;

  /// Payloads smaller than this value (bytes) are stored without compression.
  final int minimumSizeForCompression;

  /// GZip compression level: 1 (fastest) … 9 (best ratio), 6 = default.
  final int gzipLevel;

  /// When `true`, payloads larger than [isolateThreshold] bytes are
  /// compressed inside a Dart Isolate to keep the UI thread responsive.
  final bool useIsolateForLargeData;

  /// Byte threshold above which an Isolate is used.
  final int isolateThreshold;

  @override
  String toString() =>
      'CompressionConfig(strategy=${strategy.name}, '
      'minSize=$minimumSizeForCompression, gzipLevel=$gzipLevel)';
}
