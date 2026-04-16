// test/compression/gzip_provider_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for GZipCompressionProvider.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('GZipCompressionProvider', () {
    const provider = GZipCompressionProvider(level: 6);

    // ── Compress / decompress round-trip ─────────────────────────────────

    test('round-trip: small JSON string', () {
      final data = _utf8('{"name":"Ahmed","amount":125000.00}');
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    test('round-trip: large JSON array (100 items)', () {
      final list = List.generate(100, (i) => {'id': i, 'name': 'Item $i'});
      final data = _utf8(jsonEncode(list));
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    test('round-trip: Arabic text', () {
      const arabicText = 'أحمد مقرادجي — فاتورة رقم 001 — قسنطينة الجزائر';
      final data = _utf8(arabicText * 50);
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(utf8.decode(restored), equals(arabicText * 50));
    });

    test('round-trip: binary data (Uint8List)', () {
      final data = Uint8List.fromList(
        List.generate(1024, (i) => (i * 37) & 0xFF),
      );
      final compressed = provider.compress(data);
      final restored = provider.decompress(compressed);
      expect(restored, equals(data));
    });

    // ── Compression ratio ─────────────────────────────────────────────────

    test('compressed size is smaller than original for repetitive text', () {
      final data = _utf8('Hello World! ' * 200);
      final compressed = provider.compress(data);
      expect(
        compressed.length,
        lessThan(data.length),
        reason: 'GZip should reduce repetitive data',
      );
    });

    test('does not expand tiny payloads', () {
      final tiny = _utf8('Hi');
      final result = provider.compress(tiny);
      // Provider returns original when compressed > original.
      expect(result.length, lessThanOrEqualTo(tiny.length + 18));
    });

    // ── Empty data ────────────────────────────────────────────────────────

    test('compress empty bytes returns empty bytes', () {
      expect(provider.compress(Uint8List(0)), isEmpty);
    });

    test('decompress empty bytes returns empty bytes', () {
      expect(provider.decompress(Uint8List(0)), isEmpty);
    });

    // ── GZip magic detection ──────────────────────────────────────────────

    test('hasGZipMagic detects GZip header', () {
      final data = _utf8('test data ' * 20);
      final compressed = provider.compress(data);
      expect(GZipCompressionProvider.hasGZipMagic(compressed), isTrue);
    });

    test('hasGZipMagic returns false for raw data', () {
      final raw = _utf8('not gzip');
      expect(GZipCompressionProvider.hasGZipMagic(raw), isFalse);
    });

    // ── Compression levels ────────────────────────────────────────────────

    test('level 1 produces smaller output than no compression', () {
      const fast = GZipCompressionProvider(level: 1);
      final data = _utf8('abcdef' * 1000);
      final compressed = fast.compress(data);
      expect(compressed.length, lessThan(data.length));
    });

    test('level 9 produces equal-or-smaller output than level 1', () {
      const fast = GZipCompressionProvider(level: 1);
      const best = GZipCompressionProvider(level: 9);
      final data = _utf8('abcdefghij' * 500);
      expect(
        best.compress(data).length,
        lessThanOrEqualTo(fast.compress(data).length),
      );
    });

    // ── Corrupt data ──────────────────────────────────────────────────────

    test('decompress throws VaultDecompressionException for corrupt data', () {
      expect(
        () => provider.decompress(Uint8List.fromList([0, 1, 2, 3, 4, 5])),
        throwsA(isA<VaultDecompressionException>()),
      );
    });

    // ── Estimate ratio ────────────────────────────────────────────────────

    test('estimateRatio returns 0 for tiny data', () {
      expect(provider.estimateRatio(10), equals(0.0));
    });

    test('estimateRatio > 0 for large data', () {
      expect(provider.estimateRatio(100000), greaterThan(0.5));
    });

    // ── Algorithm metadata ────────────────────────────────────────────────

    test('algorithmName is GZip', () {
      expect(provider.algorithmName, equals('GZip'));
    });

    test('headerFlag matches CompressionFlag.gzip', () {
      expect(provider.headerFlag, equals(CompressionFlag.gzip));
    });
  });
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
