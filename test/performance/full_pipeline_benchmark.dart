// test/performance/full_pipeline_benchmark.dart
//
// Measures end-to-end save/read latency through the full pipeline.
// Run: dart test/performance/full_pipeline_benchmark.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:hive_vault/hive_vault.dart';

// ── Simulate the full pipeline without Hive (in-memory) ─────────────────────

Future<void> benchmarkPipeline({
  required String label,
  required VaultConfig config,
  required Map<String, dynamic> payload,
  int rounds = 100,
}) async {
  final compressor = CompressionFactory.create(config.compression);
  final masterKey = KeyManager.generateMasterKey();
  final encryptor = EncryptionFactory.create(config.encryption, masterKey);

  final rawBytes = BinaryProcessor.objectToBytes(payload);

  // ── Warmup ──
  for (var i = 0; i < 5; i++) {
    final comp = compressor.compress(rawBytes);
    final enc = await encryptor.encrypt(comp);
    final dec = await encryptor.decrypt(enc);
    compressor.decompress(dec);
  }

  // ── Write benchmark ──
  final swWrite = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    final comp = compressor.compress(rawBytes);
    await encryptor.encrypt(comp);
  }
  swWrite.stop();
  final avgWriteMs = swWrite.elapsedMilliseconds / rounds;

  // ── Read benchmark ──
  final comp = compressor.compress(rawBytes);
  final enc = await encryptor.encrypt(comp);

  final swRead = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    final dec = await encryptor.decrypt(enc);
    compressor.decompress(dec);
  }
  swRead.stop();
  final avgReadMs = swRead.elapsedMilliseconds / rounds;

  final storedSize = (await encryptor.encrypt(comp)).length;
  final ratio = (1.0 - storedSize / rawBytes.length) * 100;

  print(
    '  $label'.padRight(30) +
        '  write: ${avgWriteMs.toStringAsFixed(2).padLeft(6)}ms'
            '  read: ${avgReadMs.toStringAsFixed(2).padLeft(6)}ms'
            '  size: ${rawBytes.length}→$storedSize bytes'
            '  saved: ${ratio.toStringAsFixed(1)}%',
  );
}

void main() async {
  print('\n═══════════════════════════════════════════════════════════════');
  print('            HiveVault — Full Pipeline Benchmark');
  print('═══════════════════════════════════════════════════════════════\n');

  // Build sample invoice payload
  final smallInvoice = {
    'number': 'INV-2026-001',
    'client': 'Ahmed Ben Ali',
    'amount': 125000.0,
    'date': '2026-04-16',
    'items': List.generate(
        5, (i) => {'name': 'Item $i', 'qty': i + 1, 'price': 1000.0 * (i + 1)}),
  };

  final largeInvoice = {
    'number': 'INV-2026-999',
    'client': 'شركة النور للاستيراد والتصدير',
    'amount': 9999999.99,
    'items': List.generate(
        100,
        (i) => {
              'code': 'SKU-${i.toString().padLeft(4, '0')}',
              'name': 'Produit numéro $i avec description longue',
              'qty': i * 3,
              'price': 1234.56 * (i + 1),
              'tva': 19.0,
            }),
    'notes':
        'Facture établie conformément à la législation fiscale algérienne. '
            'Numéro NIF: 123456789012345 — RC: 06/00-0123456B13',
  };

  final configs = [
    ('Debug (No enc/comp)', VaultConfig.debug()),
    ('GZip + AES-GCM (ERP)', VaultConfig.erp()),
    ('Lz4 + AES-CBC (Light)', VaultConfig.light()),
    ('GZip L9 + AES-GCM (MaxSec)', VaultConfig.maxSecurity()),
  ];

  print('── Small Invoice (~1KB) ──────────────────────────────────────');
  for (final c in configs) {
    await benchmarkPipeline(
      label: c.$1,
      config: c.$2,
      payload: smallInvoice,
      rounds: 50,
    );
  }

  print('\n── Large Invoice (~20KB) ─────────────────────────────────────');
  for (final c in configs) {
    await benchmarkPipeline(
      label: c.$1,
      config: c.$2,
      payload: largeInvoice,
      rounds: 20,
    );
  }

  print(
      '\nNote: Each "round" = 1 complete compress+encrypt (write) or decrypt+decompress (read).');
  print(
      'Results include PBKDF2 key derivation (100K iterations for ERP/MaxSec).');
  print('Using fast iterations (1K) would be ~100× faster for ERP preset.\n');
}
