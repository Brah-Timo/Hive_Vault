// lib/src/compression/deflate_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Deflate (ZLib) compression provider.
//
// On native platforms uses dart:io ZLibCodec.
// On Flutter Web falls back to the pure-Dart Lz4 codec.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/constants.dart';
import '../core/vault_exceptions.dart';
import 'compression_provider.dart';
import 'lz4_provider.dart';

import '_io_codec_stub.dart' if (dart.library.io) '_io_codec_native.dart';

/// Deflate (ZLib) compression provider.
///
/// - **Native**: uses `dart:io ZLibCodec`.
/// - **Web**: falls back to the pure-Dart Lz4 implementation.
class DeflateCompressionProvider extends CompressionProvider {
  final int level;

  const DeflateCompressionProvider({this.level = 6})
      : assert(level >= -1 && level <= 9, 'Deflate level must be -1..9');

  static const _webFallback = Lz4CompressionProvider();

  @override
  String get algorithmName => kIsWeb ? 'Lz4(web-fallback)' : 'Deflate';

  @override
  int get headerFlag => kIsWeb ? CompressionFlag.lz4 : CompressionFlag.deflate;

  @override
  Uint8List compress(Uint8List data) {
    if (data.isEmpty) return data;
    if (kIsWeb) return _webFallback.compress(data);
    try {
      final compressed = ioDeflateCompress(data, level);
      return compressed.length < data.length ? compressed : data;
    } catch (e) {
      throw VaultCompressionException('Deflate compression failed', cause: e);
    }
  }

  @override
  Uint8List decompress(Uint8List compressedData) {
    if (compressedData.isEmpty) return compressedData;
    if (kIsWeb) return _webFallback.decompress(compressedData);
    try {
      return ioDeflateDecompress(compressedData);
    } catch (e) {
      throw VaultDecompressionException(
          'Deflate decompression failed — data may be corrupt',
          cause: e);
    }
  }

  @override
  double estimateRatio(int originalSize) {
    if (originalSize < kDefaultMinCompressionSize) return 0.0;
    if (originalSize < 256) return 0.22;
    if (originalSize < 1024) return 0.42;
    if (originalSize < 16384) return 0.62;
    return 0.72;
  }

  @override
  bool isWorthCompressing(int sizeBytes) => estimateRatio(sizeBytes) > 0.05;
}
