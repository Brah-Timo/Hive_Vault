// lib/src/compression/_io_codec_stub.dart
// ─────────────────────────────────────────────────────────────────────────────
// Web stub: dart:io is not available on Flutter Web.
// These functions are never actually called on web because GZipCompressionProvider
// and DeflateCompressionProvider check kIsWeb and delegate to the Lz4 fallback
// before reaching any io call. These stubs exist only to satisfy the Dart
// analyser / tree-shaker on web builds.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

Uint8List ioGzipCompress(Uint8List data, int level) =>
    throw UnsupportedError('GZip not available on web — use Lz4 instead');

Uint8List ioGzipDecompress(Uint8List data) =>
    throw UnsupportedError('GZip not available on web — use Lz4 instead');

Uint8List ioDeflateCompress(Uint8List data, int level) =>
    throw UnsupportedError('Deflate not available on web — use Lz4 instead');

Uint8List ioDeflateDecompress(Uint8List data) =>
    throw UnsupportedError('Deflate not available on web — use Lz4 instead');
