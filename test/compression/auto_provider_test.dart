// test/compression/auto_provider_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for AutoCompressionProvider.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('AutoCompressionProvider', () {
    const auto = AutoCompressionProvider(largeThreshold: 1024);

    // ── Algorithm selection ───────────────────────────────────────────────

    test('selects Lz4 for medium data (< largeThreshold)', () {
      final data = _utf8('medium payload ' * 30); // ~450 bytes
      final provider = auto.selectFor(data.length);
      expect(provider, isA<Lz4CompressionProvider>());
    });

    test('selects GZip for large data (≥ largeThreshold)', () {
      final data = _utf8('large payload ' * 100); // ~1400 bytes
      final provider = auto.selectFor(data.length);
      expect(provider, isA<GZipCompressionProvider>());
    });

    test('selects None for tiny data (< minSize)', () {
      final data = _utf8('tiny');
      final provider = auto.selectFor(data.length);
      expect(provider, isA<NoCompressionProvider>());
    });

    // ── Round-trip: medium data ───────────────────────────────────────────

    test('round-trip: medium JSON (Lz4 path)', () {
      final data = _utf8(jsonEncode({'name': 'Ahmed', 'items': List.generate(20, (i) => i)}));
      final compressed = auto.compress(data);
      final restored = auto.decompress(compressed);
      expect(restored, equals(data));
    });

    // ── Round-trip: large data ────────────────────────────────────────────

    test('round-trip: large JSON (GZip path)', () {
      final list = List.generate(200, (i) => {'id': i, 'name': 'Product $i', 'price': i * 100.5});
      final data = _utf8(jsonEncode(list));
      expect(data.length, greaterThanOrEqualTo(1024));
      final compressed = auto.compress(data);
      final restored = auto.decompress(compressed);
      expect(restored, equals(data));
    });

    // ── Passthrough for tiny data ─────────────────────────────────────────

    test('does not compress tiny data', () {
      final tiny = _utf8('ab'); // 2 bytes — below minSize
      final result = auto.compress(tiny);
      expect(result, equals(tiny)); // returned unchanged
    });

    // ── headerFlagFor ─────────────────────────────────────────────────────

    test('headerFlagFor returns none for tiny data', () {
      expect(auto.headerFlagFor(10), equals(CompressionFlag.none));
    });

    test('headerFlagFor returns lz4 for medium data', () {
      expect(auto.headerFlagFor(500), equals(CompressionFlag.lz4));
    });

    test('headerFlagFor returns gzip for large data', () {
      expect(auto.headerFlagFor(5000), equals(CompressionFlag.gzip));
    });

    // ── Empty data ────────────────────────────────────────────────────────

    test('compress and decompress empty bytes', () {
      expect(auto.compress(Uint8List(0)), isEmpty);
      expect(auto.decompress(Uint8List(0)), isEmpty);
    });
  });
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
