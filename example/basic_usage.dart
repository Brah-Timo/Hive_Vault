// example/basic_usage.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Basic usage example.
// ─────────────────────────────────────────────────────────────────────────────
//
// Run with: dart run example/basic_usage.dart
//
// Prerequisites:
//   1. Run `flutter pub get` in the project root.
//   2. This example uses VaultConfig.debug() which disables encryption
//      so it can run without a Flutter environment (no Keychain/Keystore).

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:hive_vault/hive_vault.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sample data models (plain Dart Maps — no code generation required)
// ─────────────────────────────────────────────────────────────────────────────

final kSampleClient = {
  'code': 'CLI-001',
  'name': 'Ahmed Mekraji',
  'city': 'Constantine',
  'phone': '+213 555 123 456',
  'email': 'ahmed.mekraji@example.com',
  'balance': 150000.00,
};

final kSampleInvoice = {
  'number': 'INV-2026-001',
  'clientCode': 'CLI-001',
  'client': 'Ahmed Mekraji',
  'date': '2026-04-16',
  'dueDate': '2026-05-16',
  'amount': 125000.00,
  'tax': 9.0,
  'total': 136250.00,
  'status': 'PENDING',
  'items': [
    {'sku': 'LAPTOP-PRO', 'name': 'Laptop Pro 15"', 'qty': 2, 'price': 55000},
    {'sku': 'PRINT-A4', 'name': 'Laser Printer A4', 'qty': 1, 'price': 15000},
  ],
};

final kSamplePayslip = {
  'number': 'PAY-2026-04-001',
  'employeeId': 'EMP-001',
  'employeeName': 'Fatima Bouzid',
  'department': 'IT',
  'period': '2026-04',
  'baseSalary': 85000.0,
  'overtime': 8500.0,
  'bonus': 5000.0,
  'deductions': 12750.0,
  'netSalary': 85750.0,
};

// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  print('╔══════════════════════════════════════════════════════╗');
  print('║           HiveVault — Basic Usage Example            ║');
  print('╚══════════════════════════════════════════════════════╝\n');

  // ── 1. Initialise Hive ──────────────────────────────────────────────────
  final tempDir = await Directory.systemTemp.createTemp('hive_vault_demo_');
  Hive.init(tempDir.path);
  print('📁 Hive initialised at: ${tempDir.path}');

  // ── 2. Open vault ───────────────────────────────────────────────────────
  final vault = await HiveVault.create(
    boxName: 'demo_vault',
    config: VaultConfig.debug(), // Plaintext for demo; use .erp() in production
  );
  await vault.initialize();
  print('🔐 Vault opened (debug mode — no encryption)\n');

  // ── 3. Save data ────────────────────────────────────────────────────────
  print('▶ Saving client…');
  await vault.secureSave(
    kSampleClient['code']!,
    kSampleClient,
    searchableText: '${kSampleClient['code']} ${kSampleClient['name']} '
        '${kSampleClient['city']}',
  );

  print('▶ Saving invoice…');
  await vault.secureSave(
    kSampleInvoice['number']!,
    kSampleInvoice,
    searchableText: '${kSampleInvoice['number']} ${kSampleInvoice['client']} '
        'laptop printer invoice',
  );

  print('▶ Saving payslip (sensitive data)…');
  await vault.secureSave(
    kSamplePayslip['number']!,
    kSamplePayslip,
    sensitivity: SensitivityLevel.high,
    searchableText:
        '${kSamplePayslip['number']} ${kSamplePayslip['employeeName']} '
        '${kSamplePayslip['department']} ${kSamplePayslip['period']}',
  );
  print('✅ All records saved.\n');

  // ── 4. Retrieve data ────────────────────────────────────────────────────
  print('▶ Retrieving client CLI-001…');
  final client = await vault.secureGet<Map>('CLI-001');
  print('  Name: ${client?['name']}');
  print('  City: ${client?['city']}');
  print('  Balance: ${client?['balance']} DZD\n');

  print('▶ Retrieving invoice INV-2026-001…');
  final invoice = await vault.secureGet<Map>('INV-2026-001');
  print('  Client: ${invoice?['client']}');
  print('  Total:  ${invoice?['total']} DZD');
  print('  Status: ${invoice?['status']}\n');

  // ── 5. Search ───────────────────────────────────────────────────────────
  print('▶ Searching for "Ahmed"…');
  final ahmedResults = await vault.secureSearch<Map>('Ahmed');
  print('  Found ${ahmedResults.length} record(s):');
  for (final r in ahmedResults) {
    print('    → ${r['name'] ?? r['client'] ?? r['number']}');
  }

  print('\n▶ Searching for "Fatima" (payslip)…');
  final fatima = await vault.secureSearch<Map>('Fatima');
  print('  Found ${fatima.length} record(s).');

  print('\n▶ Prefix search for "INV"…');
  final invResults = await vault.secureSearchPrefix<Map>('INV');
  print('  Found ${invResults.length} invoice(s).\n');

  // ── 6. Batch operations ─────────────────────────────────────────────────
  print('▶ Batch save: 5 products…');
  await vault.secureSaveBatch({
    for (int i = 1; i <= 5; i++)
      'PRD-$i': {
        'id': 'PRD-$i',
        'name': 'Product $i',
        'price': i * 1000.0,
        'stock': i * 10,
      },
  });
  print('✅ 5 products saved.\n');

  print('▶ Batch get: PRD-1, PRD-3, PRD-5…');
  final products = await vault.secureGetBatch(['PRD-1', 'PRD-3', 'PRD-5']);
  for (final e in products.entries) {
    print('  ${e.key}: ${e.value['name']} — ${e.value['price']} DZD');
  }

  // ── 7. Stats ────────────────────────────────────────────────────────────
  print('\n▶ Vault statistics:');
  final stats = await vault.getStats();
  print(stats);

  // ── 8. Audit log ────────────────────────────────────────────────────────
  print('▶ Recent audit entries (last 5):');
  final log = vault.getAuditLog(limit: 5);
  for (final entry in log) {
    print('  $entry');
  }

  // ── 9. getAllKeys ────────────────────────────────────────────────────────
  print('\n▶ All stored keys:');
  final keys = await vault.getAllKeys();
  print('  ${keys.join(', ')}\n');

  // ── 10. Delete ──────────────────────────────────────────────────────────
  print('▶ Deleting PRD-1…');
  await vault.secureDelete('PRD-1');
  print('  PRD-1 exists: ${await vault.secureContains('PRD-1')}');

  // ── 11. Close ───────────────────────────────────────────────────────────
  await vault.close();
  print('\n🔒 Vault closed.');

  // Cleanup temp dir
  await tempDir.delete(recursive: true);
  print('🧹 Temp directory cleaned up.\n');
  print('✅ Example completed successfully!');
}
