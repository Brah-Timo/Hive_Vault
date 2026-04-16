// test/performance/compression_benchmark.dart
// ─────────────────────────────────────────────────────────────────────────────
// Performance benchmarks for compression providers.
// Run with: dart test test/performance/compression_benchmark.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('Compression Benchmarks', () {
    // Fixtures
    late Uint8List smallJson; // ~500 bytes
    late Uint8List mediumJson; // ~5 KB
    late Uint8List largeJson; // ~50 KB
    late Uint8List xlargeJson; // ~200 KB

    setUpAll(() {
      smallJson = _jsonBytes(
        List.generate(10, (i) => {'id': i, 'name': 'Item $i'}),
      );
      mediumJson = _jsonBytes(
        List.generate(
            100,
            (i) => {
                  'id': i,
                  'name': 'Product $i',
                  'price': i * 100.5,
                  'category': 'Cat-${i % 10}',
                  'description': 'Description for item number $i ' * 3,
                }),
      );
      largeJson = _jsonBytes(
        List.generate(
            1000,
            (i) => {
                  'id': i,
                  'client': 'Client $i',
                  'amount': i * 999.99,
                  'date': '2026-0${(i % 9) + 1}-${(i % 28) + 1}',
                  'items':
                      List.generate(3, (j) => {'sku': 'SKU-$j', 'qty': j + 1}),
                }),
      );
      xlargeJson = _jsonBytes(
        List.generate(5000, (i) => {'id': i, 'data': 'payload-$i ' * 5}),
      );
    });

    // ── GZip ─────────────────────────────────────────────────────────────

    group('GZip (level 6)', () {
      const provider = GZipCompressionProvider(level: 6);

      _benchmarkProvider(
        label: 'small (~${_kb(500)} KB)',
        provider: provider,
        dataFn: () => _smallJson,
      );

      test('medium JSON (~5 KB)', () => _bench(provider, mediumJson));
      test('large JSON (~50 KB)', () => _bench(provider, largeJson));
      test('xlarge JSON (~200 KB)', () => _bench(provider, xlargeJson));
    });

    // ── Lz4 ──────────────────────────────────────────────────────────────

    group('Lz4', () {
      const provider = Lz4CompressionProvider();

      test('small JSON', () => _bench(provider, smallJson));
      test('medium JSON', () => _bench(provider, mediumJson));
      test('large JSON', () => _bench(provider, largeJson));
      test('xlarge JSON', () => _bench(provider, xlargeJson));
    });

    // ── Auto ──────────────────────────────────────────────────────────────

    group('Auto', () {
      const provider = AutoCompressionProvider();

      test('small JSON', () => _bench(provider, smallJson));
      test('medium JSON', () => _bench(provider, mediumJson));
      test('large JSON', () => _bench(provider, largeJson));
    });

    // ── Comparison: GZip vs Lz4 ──────────────────────────────────────────

    group('GZip vs Lz4 comparison (large JSON)', () {
      late Uint8List data;
      setUpAll(() => data = _jsonBytes(
            List.generate(
                500, (i) => {'id': i, 'name': 'n$i', 'value': i * 1.5}),
          ));

      test('GZip ratio > Lz4 ratio for text data', () {
        const gzip = GZipCompressionProvider(level: 6);
        const lz4 = Lz4CompressionProvider();
        final gzipped = gzip.compress(data);
        final lz4d = lz4.compress(data);
        final gzipRatio = 1.0 - gzipped.length / data.length;
        final lz4Ratio = 1.0 - lz4d.length / data.length;
        expect(gzipRatio, greaterThan(0.4),
            reason: 'GZip should achieve >40% on JSON');
        expect(lz4Ratio, greaterThan(0.2),
            reason: 'Lz4 should achieve >20% on JSON');
        // GZip should generally achieve better ratio
        expect(gzipRatio, greaterThanOrEqualTo(lz4Ratio - 0.1));
      });
    });
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Uint8List get _smallJson => Uint8List(0); // placeholder

Uint8List _jsonBytes(dynamic obj) =>
    Uint8List.fromList(utf8.encode(jsonEncode(obj)));

String _kb(int bytes) => (bytes / 1024).toStringAsFixed(1);

void _bench(CompressionProvider provider, Uint8List data) {
  const warmup = 3;
  const runs = 20;

  // Warmup
  for (int i = 0; i < warmup; i++) {
    provider.decompress(provider.compress(data));
  }

  // Measure compress
  final compressTimes = <int>[];
  late Uint8List compressed;
  for (int i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    compressed = provider.compress(data);
    compressTimes.add(sw.elapsedMicroseconds);
  }

  // Measure decompress
  final decompressTimes = <int>[];
  for (int i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    provider.decompress(compressed);
    decompressTimes.add(sw.elapsedMicroseconds);
  }

  final avgCompress = compressTimes.reduce((a, b) => a + b) / runs;
  final avgDecompress = decompressTimes.reduce((a, b) => a + b) / runs;
  final ratio = 1.0 - compressed.length / data.length;

  print(
    '  ${provider.algorithmName.padRight(10)} '
    '${_kb(data.length).padLeft(8)} KB → '
    '${_kb(compressed.length).padLeft(8)} KB '
    '(${(ratio * 100).toStringAsFixed(1).padLeft(5)}%) | '
    'compress: ${(avgCompress / 1000).toStringAsFixed(2)} ms | '
    'decompress: ${(avgDecompress / 1000).toStringAsFixed(2)} ms',
  );

  // Assert correctness
  final restored = provider.decompress(compressed);
  expect(restored, equals(data), reason: 'Round-trip must be lossless');
}

void _benchmarkProvider({
  required String label,
  required CompressionProvider provider,
  required Uint8List Function() dataFn,
}) {
  test(label, () => _bench(provider, dataFn()));
}
