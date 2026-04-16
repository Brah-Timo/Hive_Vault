// lib/src/compression/auto_compression_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Auto-selection compression provider.
// Chooses the best algorithm at runtime based on payload size and content.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import '../core/constants.dart';
import '../core/compression_config.dart';
import 'compression_provider.dart';
import 'gzip_provider.dart';
import 'lz4_provider.dart';
import 'deflate_provider.dart';
import 'no_compression_provider.dart';

/// Automatically selects the most appropriate compression algorithm:
///
/// | Condition                            | Selected algorithm  |
/// |--------------------------------------|---------------------|
/// | data < [_tinyThreshold]              | None                |
/// | [_tinyThreshold] ≤ data < [largeThreshold] | Lz4 (fast)   |
/// | data ≥ [largeThreshold]              | GZip (best ratio)   |
///
/// On decompress the algorithm is detected from the embedded magic bytes.
class AutoCompressionProvider extends CompressionProvider {
  /// Data smaller than this (bytes) is not compressed.
  static const int _tinyThreshold = kDefaultMinCompressionSize;

  /// Data larger than this (bytes) uses GZip; smaller uses Lz4.
  final int largeThreshold;

  final GZipCompressionProvider _gzip;
  final Lz4CompressionProvider _lz4;
  static const _none = NoCompressionProvider();

  const AutoCompressionProvider({
    this.largeThreshold = 4096,
    GZipCompressionProvider? gzip,
    Lz4CompressionProvider? lz4,
  })  : _gzip = gzip ?? const GZipCompressionProvider(level: 6),
        _lz4 = lz4 ?? const Lz4CompressionProvider();

  @override
  String get algorithmName => 'Auto';

  /// Auto provider has no fixed flag — the flag is set per-compress call.
  @override
  int get headerFlag => CompressionFlag.none;

  @override
  Uint8List compress(Uint8List data) {
    if (data.length < _tinyThreshold) return data;
    if (data.length >= largeThreshold) {
      return _gzip.compress(data);
    }
    return _lz4.compress(data);
  }

  @override
  Uint8List decompress(Uint8List compressedData) {
    if (compressedData.isEmpty) return compressedData;

    if (GZipCompressionProvider.hasGZipMagic(compressedData)) {
      return _gzip.decompress(compressedData);
    }
    if (Lz4CompressionProvider.hasLz4Magic(compressedData)) {
      return _lz4.decompress(compressedData);
    }
    // Fallback — assume no compression was applied (data is raw).
    return compressedData;
  }

  /// Returns the concrete provider that would be selected for [sizeBytes].
  CompressionProvider selectFor(int sizeBytes) {
    if (sizeBytes < _tinyThreshold) return _none;
    if (sizeBytes >= largeThreshold) return _gzip;
    return _lz4;
  }

  /// Returns the header flag of the provider that handles [sizeBytes].
  int headerFlagFor(int sizeBytes) {
    if (sizeBytes < _tinyThreshold) return CompressionFlag.none;
    if (sizeBytes >= largeThreshold) return CompressionFlag.gzip;
    return CompressionFlag.lz4;
  }

  @override
  double estimateRatio(int originalSize) {
    if (originalSize < _tinyThreshold) return 0.0;
    if (originalSize >= largeThreshold)
      return _gzip.estimateRatio(originalSize);
    return _lz4.estimateRatio(originalSize);
  }

  @override
  bool isWorthCompressing(int sizeBytes) => sizeBytes >= _tinyThreshold;
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory: instantiates the correct CompressionProvider from a config object.
// Used by VaultFactory so that the main impl does not import strategy details.
// ─────────────────────────────────────────────────────────────────────────────

/// Creates the appropriate [CompressionProvider] for [config].
CompressionProvider buildCompressionProvider(CompressionConfig config) {
  switch (config.strategy) {
    case CompressionStrategy.gzip:
      return GZipCompressionProvider(level: config.gzipLevel);
    case CompressionStrategy.lz4:
      return const Lz4CompressionProvider();
    case CompressionStrategy.deflate:
      return DeflateCompressionProvider(level: config.gzipLevel);
    case CompressionStrategy.auto:
      return AutoCompressionProvider(
        largeThreshold: config.isolateThreshold,
        gzip: GZipCompressionProvider(level: config.gzipLevel),
      );
    case CompressionStrategy.none:
      return const NoCompressionProvider();
  }
}
