// lib/src/compression/no_compression_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Pass-through provider (no compression).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import '../core/constants.dart';
import 'compression_provider.dart';

/// A [CompressionProvider] that performs no compression at all.
///
/// Use this for:
/// - Already-compressed binary data (images, audio, zip files).
/// - Debug/test builds where readability of raw storage is needed.
/// - Very small payloads where compression overhead exceeds any benefit.
class NoCompressionProvider extends CompressionProvider {
  const NoCompressionProvider();

  @override
  String get algorithmName => 'None';

  @override
  int get headerFlag => CompressionFlag.none;

  @override
  Uint8List compress(Uint8List data) => data;

  @override
  Uint8List decompress(Uint8List compressedData) => compressedData;

  @override
  double estimateRatio(int originalSize) => 0.0;

  @override
  bool isWorthCompressing(int sizeBytes) => false;
}
