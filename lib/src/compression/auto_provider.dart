// lib/src/compression/auto_provider.dart
//
// HiveVault — Adaptive compression: picks the best algorithm at runtime.
//
// Decision logic:
//   payload < minimumSizeForCompression  →  no compression
//   payload < sizeThreshold              →  Lz4  (speed priority)
//   payload ≥ sizeThreshold              →  GZip (ratio priority)
//
// On decompress, the GZip magic header is checked first; if absent, Lz4 is tried.

import 'dart:typed_data';

import '../core/constants.dart';
import '../core/vault_exceptions.dart';
import 'compression_provider.dart';
import 'gzip_provider.dart';
import 'lz4_provider.dart';
import 'no_compression_provider.dart';

/// Selects GZip or Lz4 dynamically based on payload size.
class AutoCompressionProvider extends CompressionProvider {
  AutoCompressionProvider({
    int gzipLevel = kDefaultGZipLevel,
    int sizeThreshold = 4096, // 4 KB
    int minSize = kDefaultMinCompressSize,
  })  : _gzip = GZipCompressionProvider(level: gzipLevel),
        _lz4 = const Lz4CompressionProvider(),
        _none = const NoCompressionProvider(),
        _sizeThreshold = sizeThreshold,
        _minSize = minSize;

  final GZipCompressionProvider _gzip;
  final Lz4CompressionProvider _lz4;
  final NoCompressionProvider _none;
  final int _sizeThreshold;
  final int _minSize;

  @override
  String get algorithmName => 'Auto';

  @override
  int get headerFlag =>
      kCompressionGZip; // flag is set by the actual provider used

  // ── Compress ──────────────────────────────────────────────────────────────

  @override
  Uint8List compress(Uint8List data) {
    if (data.length < _minSize) return data; // too small to benefit

    if (data.length >= _sizeThreshold) {
      return _gzip.compress(data);
    }
    return _lz4.compress(data);
  }

  /// Auto-select returns the header flag of the *actual* provider used.
  /// Callers that need the correct flag should use [compressWithFlag].
  AutoCompressResult compressWithFlag(Uint8List data) {
    if (data.length < _minSize) {
      return AutoCompressResult(data: data, flag: kCompressionNone);
    }
    if (data.length >= _sizeThreshold) {
      return AutoCompressResult(
        data: _gzip.compress(data),
        flag: kCompressionGZip,
      );
    }
    return AutoCompressResult(
      data: _lz4.compress(data),
      flag: kCompressionLz4,
    );
  }

  // ── Decompress ────────────────────────────────────────────────────────────

  @override
  Uint8List decompress(Uint8List compressedData) {
    if (compressedData.isEmpty) return compressedData;

    // Check GZip magic header first
    if (_isGZipHeader(compressedData)) {
      return _gzip.decompress(compressedData);
    }

    // Try Lz4 (no universal magic — assume Lz4 if not GZip)
    try {
      return _lz4.decompress(compressedData);
    } catch (_) {
      // Last resort: data may be uncompressed
      try {
        return _none.decompress(compressedData);
      } catch (e) {
        throw CompressionException(
            'AutoCompressionProvider: could not detect compression format.', e);
      }
    }
  }

  /// Decompress using the explicit [flag] stored in the payload header.
  Uint8List decompressWithFlag(Uint8List compressedData, int flag) {
    switch (flag) {
      case kCompressionNone:
        return compressedData;
      case kCompressionGZip:
        return _gzip.decompress(compressedData);
      case kCompressionLz4:
        return _lz4.decompress(compressedData);
      default:
        throw CompressionException(
            'AutoCompressionProvider: unknown compression flag $flag.');
    }
  }

  @override
  double estimateRatio(int originalSize) {
    if (originalSize < _minSize) return 0.0;
    if (originalSize >= _sizeThreshold)
      return _gzip.estimateRatio(originalSize);
    return _lz4.estimateRatio(originalSize);
  }

  @override
  bool canDetect(Uint8List data) => _isGZipHeader(data);

  bool _isGZipHeader(Uint8List data) =>
      data.length >= 2 && data[0] == kGZipByte0 && data[1] == kGZipByte1;
}

/// Result returned by [AutoCompressionProvider.compressWithFlag].
class AutoCompressResult {
  const AutoCompressResult({required this.data, required this.flag});

  /// Compressed (or unchanged) bytes.
  final Uint8List data;

  /// Header flag that must be embedded in the payload.
  final int flag;
}
