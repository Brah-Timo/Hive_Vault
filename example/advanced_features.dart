// example/advanced_features.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Advanced features demo.
// Covers: TTL, MultiBoxVault, ReactiveVault, VaultHealthChecker, Export/Import.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:hive_vault/hive_vault.dart';
import 'package:hive_vault/src/impl/multi_box_vault.dart';
import 'package:hive_vault/src/impl/reactive_vault.dart';
import 'package:hive_vault/src/impl/ttl_manager.dart';
import 'package:hive_vault/src/impl/vault_health.dart';

void main() async {
  print('╔═══════════════════════════════════════════════════════════╗');
  print('║         HiveVault — Advanced Features Example             ║');
  print('╚═══════════════════════════════════════════════════════════╝\n');

  final tempDir = await Directory.systemTemp.createTemp('hive_adv_');
  Hive.init(tempDir.path);

  // ══════════════════════════════════════════════════════════════════════════
  //  1. MultiBoxVault — ERP module isolation
  // ══════════════════════════════════════════════════════════════════════════
  print('▶ [1] MultiBoxVault — ERP module isolation');

  final erp = MultiBoxVault(
    defaultConfig: VaultConfig.debug(),
    modules: ['clients', 'invoices', 'products'],
    moduleConfigs: {
      // Override HR module with maximum security
      'payslips': VaultConfig.debug().copyWith(enableAuditLog: true),
    },
  );
  await erp.initialize();

  // Each module is a fully independent encrypted vault
  await erp['clients'].secureSave('CLI-001', {'name': 'Ahmed Mekraji'});
  await erp['invoices'].secureSave('INV-001', {'amount': 50000});
  await erp['products'].secureSave('PRD-001', {'name': 'Laptop Pro'});

  final client = await erp['clients'].secureGet<Map>('CLI-001');
  print('  Client: ${client?['name']}');
  print('  Modules: ${erp.moduleNames.join(', ')}\n');

  // Cross-module search — not yet (index per-module, no shared index)
  await erp.close();

  // ══════════════════════════════════════════════════════════════════════════
  //  2. ReactiveVault — Stream-based change notification
  // ══════════════════════════════════════════════════════════════════════════
  print('▶ [2] ReactiveVault — Stream-based change notifications');

  final innerVault = await HiveVault.open(
    boxName: 'reactive_demo',
    config: VaultConfig.debug(),
  );
  final reactive = ReactiveVault(innerVault);

  // Subscribe to all events
  final subscription = reactive.watchAll.listen((event) {
    print('  📡 Event: ${event.type.name} → "${event.key}"');
  });

  // Subscribe to a specific key
  final keySubscription = reactive.watch('SPECIAL-KEY').listen((event) {
    print('  🔔 SPECIAL-KEY changed: ${event.type.name}');
  });

  await reactive.secureSave('KEY-1', {'x': 1});
  await reactive.secureSave('SPECIAL-KEY', {'secret': 42});
  await reactive.secureDelete('KEY-1');

  await Future.delayed(const Duration(milliseconds: 50)); // Let streams flush
  await subscription.cancel();
  await keySubscription.cancel();
  await reactive.close();
  print();

  // ══════════════════════════════════════════════════════════════════════════
  //  3. TTL Manager — Auto-expiring cache tokens
  // ══════════════════════════════════════════════════════════════════════════
  print('▶ [3] TtlManager — Time-To-Live for session tokens');

  final sessionVault = await HiveVault.open(
    boxName: 'sessions',
    config: VaultConfig.debug(),
  );
  final ttl = TtlManager(dataBoxName: 'sessions');
  await ttl.initialize();

  // Save session with 24h TTL
  await sessionVault.secureSave('TOKEN-ABC', {
    'userId': 'USR-001',
    'token': 'abc123xyz',
    'createdAt': DateTime.now().toIso8601String(),
  });
  await ttl.setExpiry('TOKEN-ABC', const Duration(hours: 24));

  // Check expiry
  final expiry = ttl.getExpiry('TOKEN-ABC');
  final remaining = ttl.getRemaining('TOKEN-ABC');
  print('  Token expires at: ${expiry?.toIso8601String()}');
  print(
      '  Time remaining: ${remaining?.inHours}h ${remaining?.inMinutes.remainder(60)}m');
  print('  Is expired: ${ttl.isExpired('TOKEN-ABC')}');

  // Save a token with very short TTL (already expired)
  await sessionVault.secureSave('TOKEN-OLD', {'expired': true});
  await ttl.setExpiry('TOKEN-OLD', const Duration(milliseconds: 1));
  await Future.delayed(const Duration(milliseconds: 5));
  print('  Old token expired: ${ttl.isExpired('TOKEN-OLD')}');

  final purged = await ttl.purgeNow(
    onExpired: (key) async {
      await sessionVault.secureDelete(key);
      print('  🗑️ Purged expired key: $key');
    },
  );
  print('  Purged ${purged.length} expired token(s).\n');

  await ttl.close();
  await sessionVault.close();

  // ══════════════════════════════════════════════════════════════════════════
  //  4. VaultHealthChecker — Diagnostics
  // ══════════════════════════════════════════════════════════════════════════
  print('▶ [4] VaultHealthChecker — Diagnostics');

  final healthVault = await HiveVault.open(
    boxName: 'health_demo',
    config: VaultConfig.debug().copyWith(memoryCacheSize: 5),
  );

  // Add some data
  for (int i = 0; i < 20; i++) {
    await healthVault.secureSave('H-$i', {'id': i, 'name': 'Item $i'},
        searchableText: 'item $i name');
  }
  // Read several times to build cache stats
  for (int i = 0; i < 10; i++) {
    await healthVault.secureGet<Map>('H-${i % 5}');
  }

  final report = await VaultHealthChecker.check(healthVault);
  print(report);

  await healthVault.close();

  // ══════════════════════════════════════════════════════════════════════════
  //  5. Export / Import — Encrypted backup
  // ══════════════════════════════════════════════════════════════════════════
  print('▶ [5] Export / Import — Encrypted backup');

  final sourceVault = await HiveVault.open(
    boxName: 'export_source',
    config: VaultConfig.debug(),
  );

  await sourceVault.secureSaveBatch({
    'REC-001': {'type': 'invoice', 'amount': 10000},
    'REC-002': {'type': 'invoice', 'amount': 20000},
    'REC-003': {'type': 'receipt', 'amount': 5000},
  });

  print(
      '  Source vault: ${(await sourceVault.getStats()).totalEntries} entries');

  // Export
  final archive = await sourceVault.exportEncrypted();
  print('  Archive size: ${archive.length} bytes');

  // Import into a new vault
  final targetVault = await HiveVault.open(
    boxName: 'export_target',
    config: VaultConfig.debug(),
  );
  await targetVault.importEncrypted(archive);

  final targetStats = await targetVault.getStats();
  print('  Target vault after import: ${targetStats.totalEntries} entries');

  final rec1 = await targetVault.secureGet<Map>('REC-001');
  print('  REC-001 amount: ${rec1?['amount']}');

  await sourceVault.close();
  await targetVault.close();

  // ── Cleanup ──────────────────────────────────────────────────────────────
  await Hive.close();
  await tempDir.delete(recursive: true);

  print('\n✅ Advanced features demo completed!');
}
