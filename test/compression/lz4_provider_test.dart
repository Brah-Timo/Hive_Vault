// test/compression/lz4_provider_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for Lz4CompressionProvider (pure-Dart implementation).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('Lz4CompressionProvider', () {
    const provider = Lz4CompressionProvider();

    // ── Round-trip ────────────────────────────────────────────────────────

    test('round-trip: simple ASCII string', () {
      final data = _utf8('Hello World! This is a test of the Lz4 compressor.');
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    test('round-trip: repetitive JSON', () {
      final json = jsonEncode(
        List.generate(50, (i) => {'id': i, 'value': 'item-$i-data'}),
      );
      final data = _utf8(json);
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    test('round-trip: Arabic text', () {
      const text = 'الجزائر — قسنطينة — بوسعادة — باتنة — عنابة — وهران';
      final data = _utf8(text * 20);
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(utf8.decode(restored), equals(text * 20));
    });

    test('round-trip: binary pattern data', () {
      final data = Uint8List.fromList(
        List.generate(512, (i) => (i % 256)),
      );
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    test('round-trip: all-zeros buffer', () {
      final data = Uint8List(2048); // all zeros = highly compressible
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    // ── Size ──────────────────────────────────────────────────────────────

    test('compressed size < original for repetitive data', () {
      final data = _utf8('AAAAAABBBBBBCCCCCCDDDDDD' * 100);
      final compressed = provider.compress(data);
      expect(compressed.length, lessThan(data.length));
    });

    // ── Empty data ────────────────────────────────────────────────────────

    test('compress empty bytes returns empty', () {
      expect(provider.compress(Uint8List(0)), isEmpty);
    });

    test('decompress empty bytes returns empty', () {
      expect(provider.decompress(Uint8List(0)), isEmpty);
    });

    // ── Magic detection ───────────────────────────────────────────────────

    test('hasLz4Magic detects Lz4 header on compressed output', () {
      final data = _utf8('test ' * 50);
      final compressed = provider.compress(data);
      expect(Lz4CompressionProvider.hasLz4Magic(compressed), isTrue);
    });

    test('hasLz4Magic returns false for raw data', () {
      expect(
        Lz4CompressionProvider.hasLz4Magic(_utf8('not lz4')),
        isFalse,
      );
    });

    // ── Error handling ────────────────────────────────────────────────────

    test('decompress throws VaultDecompressionException for bad magic', () {
      final bad = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0xFF]);
      expect(
        () => provider.decompress(bad),
        throwsA(isA<VaultDecompressionException>()),
      );
    });

    // ── Algorithm metadata ────────────────────────────────────────────────

    test('algorithmName is Lz4', () {
      expect(provider.algorithmName, equals('Lz4'));
    });

    test('headerFlag matches CompressionFlag.lz4', () {
      expect(provider.headerFlag, equals(CompressionFlag.lz4));
    });

    test('estimateRatio > 0 for large data', () {
      expect(provider.estimateRatio(10000), greaterThan(0.3));
    });
  });
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
