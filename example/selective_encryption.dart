// example/selective_encryption.dart
//
// HiveVault — Field-level selective encryption demo.
//
// Strategy: split a Client record into two vault entries:
//   ┌─────────────────────────────────────────────────────┐
//   │  CLI-{id}-public   → name, city, category  (standard)│
//   │  CLI-{id}-private  → phone, email, balance (high)    │
//   └─────────────────────────────────────────────────────┘
//
// This way public fields remain searchable and the most sensitive
// fields get the strongest AES-256-GCM protection.

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:hive_vault/hive_vault.dart';

class Client {
  Client({
    required this.code,
    required this.name,
    required this.city,
    required this.category,
    required this.phone,
    required this.email,
    required this.bankAccount,
    required this.balance,
  });

  // Public fields
  final String code;
  final String name;
  final String city;
  final String category;

  // Private / sensitive fields
  final String phone;
  final String email;
  final String bankAccount;
  final double balance;
}

class SelectiveClientRepository {
  SelectiveClientRepository(this._vault);
  final HiveVaultImpl _vault;

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> saveClient(Client client) async {
    // Public portion — standard encryption, fully searchable
    await _vault.secureSave(
      '${client.code}-public',
      {
        'code': client.code,
        'name': client.name,
        'city': client.city,
        'category': client.category,
      },
      sensitivity: SensitivityLevel.standard,
      searchableText:
          '${client.code} ${client.name} ${client.city} ${client.category}',
    );

    // Private portion — high encryption, NOT indexed (no searchableText)
    await _vault.secureSave(
      '${client.code}-private',
      {
        'phone': client.phone,
        'email': client.email,
        'bankAccount': client.bankAccount,
        'balance': client.balance,
      },
      sensitivity: SensitivityLevel.high,
      // No searchableText — sensitive data must NOT appear in the index
    );
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getPublicData(String code) async {
    final data = await _vault.secureGet<Map>('$code-public');
    return data?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> getPrivateData(String code) async {
    final data = await _vault.secureGet<Map>('$code-private');
    return data?.cast<String, dynamic>();
  }

  Future<Client?> getFullClient(String code) async {
    final pub  = await getPublicData(code);
    final priv = await getPrivateData(code);
    if (pub == null || priv == null) return null;

    return Client(
      code: pub['code'] as String,
      name: pub['name'] as String,
      city: pub['city'] as String,
      category: pub['category'] as String,
      phone: priv['phone'] as String,
      email: priv['email'] as String,
      bankAccount: priv['bankAccount'] as String,
      balance: (priv['balance'] as num).toDouble(),
    );
  }

  // ── Search (public only) ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> search(String query) async {
    final results = await _vault.secureSearch<Map>(query);
    return results
        .where((r) => r.containsKey('name')) // only public records
        .map((r) => r.cast<String, dynamic>())
        .toList();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteClient(String code) async {
    await _vault.secureDeleteBatch(['$code-public', '$code-private']);
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('hive_selective_demo_');
  Hive.init(dir.path);
  print('HiveVault — Selective Encryption Demo\n══════════════════════════════════\n');

  final vault = await VaultFactory.open('clients', config: VaultConfig.debug());
  final repo  = SelectiveClientRepository(vault);

  // ── Seed ──────────────────────────────────────────────────────────────────
  final clients = [
    Client(
      code: 'CLI-001',
      name: 'Ahmed Ben Ali',
      city: 'Algiers',
      category: 'Premium',
      phone: '+213 555 123456',
      email: 'ahmed@example.dz',
      bankAccount: 'CPA 00200123456789012',
      balance: 250000.0,
    ),
    Client(
      code: 'CLI-002',
      name: 'Fatima Oukaci',
      city: 'Oran',
      category: 'Standard',
      phone: '+213 555 654321',
      email: 'fatima@example.dz',
      bankAccount: 'BNA 00300987654321098',
      balance: -15000.0,
    ),
    Client(
      code: 'CLI-003',
      name: 'Karim Bouzid',
      city: 'Constantine',
      category: 'VIP',
      phone: '+213 555 112233',
      email: 'karim@example.dz',
      bankAccount: 'CNEP 00400112233445566',
      balance: 1500000.0,
    ),
  ];

  for (final c in clients) await repo.saveClient(c);
  print('✅ Saved ${clients.length} clients (${clients.length * 2} vault entries).\n');

  // ── Search public fields ───────────────────────────────────────────────────
  final algiers = await repo.search('Algiers');
  print('🔍 Search "Algiers" — ${algiers.length} result(s):');
  for (final r in algiers) print('   ${r['code']} — ${r['name']} — ${r['city']}');
  print('');

  // ── Retrieve full client ───────────────────────────────────────────────────
  final full = await repo.getFullClient('CLI-003');
  if (full != null) {
    print('👤 Full record for CLI-003:');
    print('   Name        : ${full.name}');
    print('   City        : ${full.city} (${full.category})');
    print('   Phone       : ${full.phone}');
    print('   Email       : ${full.email}');
    print('   Bank Account: ${full.bankAccount}');
    print('   Balance     : ${full.balance} DZD');
  }
  print('');

  // ── Verify private data is NOT in index ────────────────────────────────────
  final bankSearch = await repo.search('CPA');
  print('🔒 Search "CPA" (bank account number) in index: ${bankSearch.length} result(s)');
  print('   → Bank accounts are NOT indexed, so 0 results is correct.\n');

  // ── Stats ─────────────────────────────────────────────────────────────────
  print(await vault.getStats());

  await vault.close();
  await VaultFactory.closeAll();
  print('\n✅ Selective encryption demo complete.');
}
