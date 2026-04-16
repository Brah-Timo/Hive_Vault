// example/export_import.dart
//
// HiveVault — Encrypted backup export & import demo.
//
// Demonstrates:
//   1. Save data to vault A.
//   2. Export as an encrypted binary blob.
//   3. Import the blob into a fresh vault B.
//   4. Verify data integrity across vaults.

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:hive_vault/hive_vault.dart';

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('hive_export_demo_');
  Hive.init(dir.path);
  print('HiveVault — Export/Import Demo\n════════════════════════════\n');

  // ── Vault A: populate with data ───────────────────────────────────────────
  final vaultA = await VaultFactory.open('vault_a', config: VaultConfig.debug());

  for (var i = 1; i <= 5; i++) {
    await vaultA.secureSave(
      'KEY-$i',
      {'id': i, 'message': 'Record number $i', 'value': i * 1000.0},
      searchableText: 'Record $i message value',
    );
  }
  print('✅ Vault A: saved 5 entries.\n');

  // ── Export ─────────────────────────────────────────────────────────────────
  final exportBlob = await vaultA.exportEncrypted();
  print('📦 Exported ${exportBlob.length} bytes from Vault A.');
  await vaultA.close();

  // ── Vault B: fresh empty vault ────────────────────────────────────────────
  final vaultB = await VaultFactory.open('vault_b', config: VaultConfig.debug());
  print('   Vault B before import: ${(await vaultB.getStats()).totalEntries} entries.');

  // ── Import ────────────────────────────────────────────────────────────────
  await vaultB.importEncrypted(exportBlob);
  print('   Vault B after import : ${(await vaultB.getStats()).totalEntries} entries.\n');

  // ── Verify data integrity ─────────────────────────────────────────────────
  print('🔍 Verifying all records in Vault B:');
  bool allOk = true;
  for (var i = 1; i <= 5; i++) {
    final record = await vaultB.secureGet<Map>('KEY-$i');
    final ok = record != null &&
        record['id'] == i &&
        record['message'] == 'Record number $i' &&
        record['value'] == i * 1000.0;
    print('   KEY-$i: ${ok ? "✅ OK" : "❌ MISMATCH"} — $record');
    if (!ok) allOk = false;
  }

  // ── Search in imported vault ───────────────────────────────────────────────
  final searchResults = await vaultB.secureSearch<Map>('Record');
  print('\n🔍 Search "Record" in Vault B: ${searchResults.length} results');

  await vaultB.close();
  await VaultFactory.closeAll();

  print('\n${allOk ? "✅" : "❌"} Export/Import demo ${allOk ? "PASSED" : "FAILED"}.');
}
