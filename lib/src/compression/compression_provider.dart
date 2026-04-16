// lib/src/compression/compression_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Abstract interface for all compression providers.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Contract that every compression algorithm must satisfy.
///
/// Both [compress] and [decompress] operate on raw [Uint8List] and are
/// expected to be synchronous (CPU-bound). For large payloads HiveVault
/// automatically moves the call to a background isolate.
abstract class CompressionProvider {
  // Const constructor so that subclasses can declare `const` constructors
  // while using `extends` (which requires the super-constructor to be const).
  const CompressionProvider();

  /// Algorithm name used in statistics and audit logs.
  String get algorithmName;

  /// Integer flag written into the binary payload header to identify this
  /// algorithm when decompressing. Must match one of the [CompressionFlag]
  /// constants.
  int get headerFlag;

  /// Compresses [data] and returns the compressed bytes.
  ///
  /// MUST return [data] unchanged if compression would increase the size
  /// or if [data] is empty.
  ///
  /// Throws [VaultCompressionException] on unrecoverable errors.
  Uint8List compress(Uint8List data);

  /// Decompresses [compressedData] and returns the original bytes.
  ///
  /// Throws [VaultDecompressionException] if the data is corrupt or truncated.
  Uint8List decompress(Uint8List compressedData);

  /// Estimates the compression ratio for [originalSize] bytes.
  ///
  /// Returns a value between 0.0 (no savings) and 1.0 (perfect compression).
  /// Used by the auto-strategy to choose the best algorithm.
  double estimateRatio(int originalSize);

  /// Returns `true` if this provider is likely to produce useful compression
  /// for data of [sizeBytes] bytes.
  bool isWorthCompressing(int sizeBytes) => estimateRatio(sizeBytes) > 0.05;
}
