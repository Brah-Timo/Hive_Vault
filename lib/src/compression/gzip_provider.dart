// lib/src/compression/gzip_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — GZip compression provider.
//
// On native platforms (Android, iOS, desktop) uses dart:io's GZipCodec.
// On Flutter Web dart:io is unavailable, so we fall back to the pure-Dart
// Lz4 codec — which achieves comparable compression with zero native deps.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/constants.dart';
import '../core/vault_exceptions.dart';
import 'compression_provider.dart';
import 'lz4_provider.dart'; // pure-Dart fallback for web

// dart:io is only imported on non-web builds via conditional import shim.
import '_io_codec_stub.dart' if (dart.library.io) '_io_codec_native.dart';

/// GZip compression provider.
///
/// - **Native** (Android / iOS / desktop / server): uses `dart:io GZipCodec`.
/// - **Web**: falls back to the pure-Dart Lz4 implementation, which is
///   platform-agnostic and has no native dependencies.
class GZipCompressionProvider extends CompressionProvider {
  /// GZip compression level (-1 = zlib default ≈ 6, 0 = none, 1–9 = fast→best).
  /// Ignored on web (Lz4 fallback has no level parameter).
  final int level;

  const GZipCompressionProvider({this.level = 6})
      : assert(level >= -1 && level <= 9, 'GZip level must be -1..9');

  // ─── Web fallback singleton ───────────────────────────────────────────────
  static const _webFallback = Lz4CompressionProvider();

  @override
  String get algorithmName => kIsWeb ? 'Lz4(web-fallback)' : 'GZip';

  @override
  int get headerFlag => kIsWeb ? CompressionFlag.lz4 : CompressionFlag.gzip;

  @override
  Uint8List compress(Uint8List data) {
    if (data.isEmpty) return data;
    if (kIsWeb) return _webFallback.compress(data);
    try {
      final compressed = ioGzipCompress(data, level);
      return compressed.length < data.length ? compressed : data;
    } catch (e) {
      throw VaultCompressionException('GZip compression failed', cause: e);
    }
  }

  @override
  Uint8List decompress(Uint8List compressedData) {
    if (compressedData.isEmpty) return compressedData;
    if (kIsWeb) return _webFallback.decompress(compressedData);
    try {
      return ioGzipDecompress(compressedData);
    } catch (e) {
      throw VaultDecompressionException(
          'GZip decompression failed — data may be corrupt',
          cause: e);
    }
  }

  @override
  double estimateRatio(int originalSize) {
    if (originalSize < kDefaultMinCompressionSize) return 0.0;
    if (originalSize < 256) return 0.20;
    if (originalSize < 1024) return 0.40;
    if (originalSize < 16384) return 0.60;
    return 0.70;
  }

  @override
  bool isWorthCompressing(int sizeBytes) => estimateRatio(sizeBytes) > 0.05;

  /// Returns `true` if [data] starts with the GZip magic bytes (native only).
  static bool hasGZipMagic(Uint8List data) =>
      !kIsWeb &&
      data.length >= 2 &&
      data[0] == kGZipByte0 &&
      data[1] == kGZipByte1;
}
