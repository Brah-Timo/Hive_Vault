// lib/src/binary/binary_processor.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Binary serialisation, payload framing, and checksum utilities.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;
import '../core/constants.dart';
import '../core/vault_exceptions.dart';
import 'payload_info.dart';

/// Handles all binary serialisation, framing, and integrity operations.
///
/// ## Payload layout
///
/// ```
/// [version: 1 byte]
/// [compressionFlag: 1 byte]
/// [encryptionFlag: 1 byte]
/// [dataLength: 4 bytes big-endian]
/// [data: dataLength bytes]
/// [checksum: 32 bytes SHA-256]  ← only when integrity checks are on
/// ```
///
/// Total overhead: 7 bytes header + optional 32 bytes checksum.
class BinaryProcessor {
  /// When `true` a SHA-256 checksum is appended to every payload and
  /// verified on every read.
  final bool enableIntegrityChecks;

  const BinaryProcessor({this.enableIntegrityChecks = true});

  // ═══════════════════════════════════════════════════════════════════════════
  //  Serialisation helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converts any JSON-serialisable Dart object to a UTF-8 [Uint8List].
  ///
  /// Supported types:
  /// - [Uint8List] — returned as-is.
  /// - [String] — UTF-8 encoded.
  /// - [Map], [List] — JSON-encoded then UTF-8 encoded.
  /// - [num], [bool] — converted to string then UTF-8 encoded.
  static Uint8List objectToBytes(dynamic object) {
    if (object is Uint8List) return object;
    if (object is List<int>) return Uint8List.fromList(object);
    if (object is String) return _utf8Encode(object);
    if (object is Map || object is List) {
      return _utf8Encode(jsonEncode(object));
    }
    if (object is num || object is bool) {
      return _utf8Encode(object.toString());
    }
    throw VaultPayloadException(
      'Cannot serialise ${object.runtimeType} to bytes. '
      'Supported: Uint8List, String, Map, List, num, bool.',
    );
  }

  /// Converts a [Uint8List] back to the desired type [T].
  ///
  /// Supported types: [Uint8List], [String], [Map], [List], [dynamic].
  static T bytesToObject<T>(Uint8List bytes) {
    if (T == Uint8List || T == List<int>) return bytes as T;
    final json = _utf8Decode(bytes);
    if (T == String) return json as T;
    try {
      return jsonDecode(json) as T;
    } catch (e) {
      // If JSON decode fails, return the raw string.
      if (T == dynamic || T == Object) return json as T;
      throw VaultPayloadException(
        'Cannot deserialise bytes to $T',
        cause: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Payload framing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Wraps [data] in a HiveVault binary envelope with the given flags.
  ///
  /// If [enableIntegrityChecks] is `true`, a SHA-256 checksum of [data] is
  /// appended after the payload.
  Future<Uint8List> createPayload({
    required Uint8List data,
    required int compressionFlag,
    required int encryptionFlag,
  }) async {
    final dataLen = data.length;

    // Optional checksum
    Uint8List? checksum;
    if (enableIntegrityChecks) {
      checksum = await _sha256(data);
    }

    final totalLen = kHeaderSize + dataLen + (checksum?.length ?? 0);
    final payload = Uint8List(totalLen);
    final bd = payload.buffer.asByteData();

    // Write header
    bd.setUint8(0, kPayloadVersion);
    bd.setUint8(1, compressionFlag);
    bd.setUint8(2, encryptionFlag);
    bd.setUint32(3, dataLen, Endian.big);

    // Write data
    payload.setRange(kHeaderSize, kHeaderSize + dataLen, data);

    // Write checksum
    if (checksum != null) {
      payload.setRange(kHeaderSize + dataLen, totalLen, checksum);
    }

    return payload;
  }

  /// Parses a binary envelope produced by [createPayload].
  ///
  /// Verifies the checksum if [enableIntegrityChecks] is `true`.
  ///
  /// Throws [VaultPayloadException] for malformed payloads.
  /// Throws [VaultIntegrityException] for checksum mismatches.
  Future<PayloadInfo> parsePayload(Uint8List payload) async {
    if (payload.length < kHeaderSize) {
      throw VaultPayloadException(
        'Payload too short: ${payload.length} bytes '
        '(minimum $kHeaderSize)',
      );
    }

    final bd = payload.buffer.asByteData(
      payload.offsetInBytes,
      payload.length,
    );

    final version = bd.getUint8(0);
    if (version != kPayloadVersion) {
      throw VaultPayloadException(
        'Unsupported payload version: $version '
        '(current: $kPayloadVersion)',
      );
    }

    final compressionFlag = bd.getUint8(1);
    final encryptionFlag = bd.getUint8(2);
    final dataLen = bd.getUint32(3, Endian.big);

    final expectedMinLen = kHeaderSize +
        dataLen +
        (enableIntegrityChecks ? 32 : 0);

    if (payload.length < expectedMinLen) {
      throw VaultPayloadException(
        'Payload length mismatch: expected ≥$expectedMinLen, '
        'got ${payload.length}',
      );
    }

    final data = payload.sublist(kHeaderSize, kHeaderSize + dataLen);

    // Verify checksum
    if (enableIntegrityChecks) {
      final storedChecksum = payload.sublist(kHeaderSize + dataLen);
      final actual = await _sha256(data);
      if (!_constantTimeEquals(actual, storedChecksum)) {
        throw VaultIntegrityException(
          'Payload checksum mismatch — data may be corrupt or tampered.',
        );
      }
    }

    return PayloadInfo(
      version: version,
      compressionFlag: compressionFlag,
      encryptionFlag: encryptionFlag,
      data: data,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Checksum helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Computes SHA-256 of [data].
  static Future<Uint8List> computeChecksum(Uint8List data) => _sha256(data);

  static Future<Uint8List> _sha256(Uint8List data) async {
    final hash = await crypto.Sha256().hash(data);
    return Uint8List.fromList(hash.bytes);
  }

  /// Constant-time comparison of two byte arrays (prevents timing attacks).
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ─── UTF-8 helpers ────────────────────────────────────────────────────────

  static Uint8List _utf8Encode(String s) =>
      Uint8List.fromList(utf8.encode(s));

  static String _utf8Decode(Uint8List bytes) => utf8.decode(bytes);
}
