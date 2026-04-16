// lib/src/binary/payload_info.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Binary payload metadata extracted from a stored envelope.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:meta/meta.dart';
import '../core/constants.dart';

/// Parsed representation of a HiveVault binary payload header.
///
/// Header layout (7 bytes):
///   [0]   format version  (uint8)
///   [1]   compression flag (uint8) — see [CompressionFlag]
///   [2]   encryption flag  (uint8) — see [EncryptionFlag]
///   [3..6] data length     (uint32 big-endian)
@immutable
class PayloadInfo {
  /// Format version of the payload. Only version [kPayloadVersion] is
  /// currently supported.
  final int version;

  /// Identifies the compression algorithm. Matches [CompressionFlag] values.
  final int compressionFlag;

  /// Identifies the encryption algorithm. Matches [EncryptionFlag] values.
  final int encryptionFlag;

  /// The raw payload data (after the header).
  final Uint8List data;

  const PayloadInfo({
    required this.version,
    required this.compressionFlag,
    required this.encryptionFlag,
    required this.data,
  });

  // ─── Derived helpers ──────────────────────────────────────────────────────

  bool get isCompressed => compressionFlag != CompressionFlag.none;
  bool get isEncrypted => encryptionFlag != EncryptionFlag.none;

  String get compressionLabel {
    switch (compressionFlag) {
      case CompressionFlag.gzip:    return 'GZip';
      case CompressionFlag.lz4:     return 'Lz4';
      case CompressionFlag.deflate: return 'Deflate';
      default:                      return 'None';
    }
  }

  String get encryptionLabel {
    switch (encryptionFlag) {
      case EncryptionFlag.aesGcm: return 'AES-256-GCM';
      case EncryptionFlag.aesCbc: return 'AES-256-CBC';
      default:                    return 'None';
    }
  }

  @override
  String toString() => 'PayloadInfo('
      'v$version, '
      'compression: $compressionLabel, '
      'encryption: $encryptionLabel, '
      'dataLen: ${data.length})';
}
