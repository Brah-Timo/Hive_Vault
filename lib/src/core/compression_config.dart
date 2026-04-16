// lib/src/core/compression_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Compression configuration.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';

/// Supported compression algorithms.
enum CompressionStrategy {
  /// No compression; data is stored as-is.
  none,

  /// GZip (DEFLATE with header/trailer). High compression ratio, moderate speed.
  /// Best for large JSON payloads and text-heavy data.
  gzip,

  /// Lz4 frame format. Very fast compression/decompression with moderate ratio.
  /// Best for data that needs fast access patterns.
  lz4,

  /// Raw DEFLATE (ZLib). Similar to GZip but no file header.
  deflate,

  /// Automatically selects gzip for large data and lz4 for smaller data
  /// based on [CompressionConfig.isolateThreshold].
  auto,
}

/// Immutable configuration for the compression layer.
@immutable
class CompressionConfig {
  /// Compression algorithm to use.
  final CompressionStrategy strategy;

  /// Data smaller than this value (bytes) is stored without compression.
  /// Compressing tiny payloads adds overhead without benefit.
  final int minimumSizeForCompression;

  /// GZip compression level: -1 = default, 0 = none, 1 = fastest, 9 = best.
  final int gzipLevel;

  /// When [strategy] is [CompressionStrategy.auto], data larger than this
  /// threshold (bytes) uses gzip; data smaller uses lz4.
  final int isolateThreshold;

  /// If `true`, large payloads (> [isolateThreshold]) are compressed inside a
  /// Dart isolate to avoid blocking the UI thread.
  final bool useIsolateForLargeData;

  const CompressionConfig({
    this.strategy = CompressionStrategy.gzip,
    this.minimumSizeForCompression = 64,
    this.gzipLevel = 6,
    this.isolateThreshold = 65536, // 64 KB
    this.useIsolateForLargeData = true,
  }) : assert(
          gzipLevel >= -1 && gzipLevel <= 9,
          'gzipLevel must be between -1 and 9',
        );

  // ─── Predefined presets ──────────────────────────────────────────────────

  /// Best compression ratio — ideal for large JSON datasets.
  const CompressionConfig.bestRatio()
      : this(
          strategy: CompressionStrategy.gzip,
          gzipLevel: 9,
          minimumSizeForCompression: 32,
        );

  /// Best speed — ideal for frequently read/written small records.
  const CompressionConfig.bestSpeed()
      : this(
          strategy: CompressionStrategy.lz4,
          minimumSizeForCompression: 128,
        );

  /// No compression — for debug builds or already-compressed binary data.
  const CompressionConfig.disabled()
      : this(strategy: CompressionStrategy.none);

  // ─── Equality & copy ─────────────────────────────────────────────────────

  CompressionConfig copyWith({
    CompressionStrategy? strategy,
    int? minimumSizeForCompression,
    int? gzipLevel,
    int? isolateThreshold,
    bool? useIsolateForLargeData,
  }) {
    return CompressionConfig(
      strategy: strategy ?? this.strategy,
      minimumSizeForCompression:
          minimumSizeForCompression ?? this.minimumSizeForCompression,
      gzipLevel: gzipLevel ?? this.gzipLevel,
      isolateThreshold: isolateThreshold ?? this.isolateThreshold,
      useIsolateForLargeData:
          useIsolateForLargeData ?? this.useIsolateForLargeData,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompressionConfig &&
          strategy == other.strategy &&
          minimumSizeForCompression == other.minimumSizeForCompression &&
          gzipLevel == other.gzipLevel &&
          isolateThreshold == other.isolateThreshold &&
          useIsolateForLargeData == other.useIsolateForLargeData;

  @override
  int get hashCode => Object.hash(
        strategy,
        minimumSizeForCompression,
        gzipLevel,
        isolateThreshold,
        useIsolateForLargeData,
      );

  @override
  String toString() => 'CompressionConfig('
      'strategy: $strategy, '
      'minSize: $minimumSizeForCompression, '
      'gzipLevel: $gzipLevel)';
}
