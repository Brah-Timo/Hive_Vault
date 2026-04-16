// lib/src/compression/_io_codec_native.dart
// ─────────────────────────────────────────────────────────────────────────────
// Native implementation: uses dart:io GZipCodec and ZLibCodec.
// Imported only on non-web platforms via conditional import in the providers.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';

/// Compress [data] using GZip at the given [level].
Uint8List ioGzipCompress(Uint8List data, int level) {
  final codec = GZipCodec(level: level);
  return Uint8List.fromList(codec.encode(data));
}

/// Decompress GZip-compressed [data].
Uint8List ioGzipDecompress(Uint8List data) {
  final codec = GZipCodec();
  return Uint8List.fromList(codec.decode(data));
}

/// Compress [data] using ZLib/Deflate at the given [level].
Uint8List ioDeflateCompress(Uint8List data, int level) {
  final codec = ZLibCodec(level: level);
  return Uint8List.fromList(codec.encode(data));
}

/// Decompress ZLib/Deflate-compressed [data].
Uint8List ioDeflateDecompress(Uint8List data) {
  final codec = ZLibCodec();
  return Uint8List.fromList(codec.decode(data));
}
