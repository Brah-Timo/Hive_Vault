// example/erp_example.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — ERP (gestion_commerciale_dz) integration example.
// Shows repository pattern, full ERP workflow, and selective encryption.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:hive_vault/hive_vault.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Domain models
// ═════════════════════════════════════════════════════════════════════════════

class Client {
  final String code;
  final String name;
  final String city;
  final String phone;
  final String email;
  final double balance;
  final String taxId;

  const Client({
    required this.code,
    required this.name,
    required this.city,
    required this.phone,
    required this.email,
    required this.balance,
    required this.taxId,
  });

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        code: m['code'],
        name: m['name'],
        city: m['city'],
        phone: m['phone'],
        email: m['email'],
        balance: (m['balance'] as num).toDouble(),
        taxId: m['taxId'],
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'city': city,
        'phone': phone,
        'email': email,
        'balance': balance,
        'taxId': taxId,
      };

  String get searchText => '$code $name $city';
}

class Invoice {
  final String number;
  final String clientCode;
  final String clientName;
  final DateTime date;
  final double amount;
  final double tax;
  final List<InvoiceItem> items;
  final String status;

  const Invoice({
    required this.number,
    required this.clientCode,
    required this.clientName,
    required this.date,
    required this.amount,
    required this.tax,
    required this.items,
    required this.status,
  });

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        number: m['number'],
        clientCode: m['clientCode'],
        clientName: m['clientName'],
        date: DateTime.parse(m['date']),
        amount: (m['amount'] as num).toDouble(),
        tax: (m['tax'] as num).toDouble(),
        items: (m['items'] as List).map((i) => InvoiceItem.fromMap(i)).toList(),
        status: m['status'],
      );

  Map<String, dynamic> toMap() => {
        'number': number,
        'clientCode': clientCode,
        'clientName': clientName,
        'date': date.toIso8601String().substring(0, 10),
        'amount': amount,
        'tax': tax,
        'total': amount * (1 + tax / 100),
        'items': items.map((i) => i.toMap()).toList(),
        'status': status,
      };

  String get searchText => '$number $clientCode $clientName '
      '${items.map((i) => i.name).join(' ')} '
      '${date.year} ${date.month}';
}

class InvoiceItem {
  final String sku;
  final String name;
  final int qty;
  final double price;

  const InvoiceItem({
    required this.sku,
    required this.name,
    required this.qty,
    required this.price,
  });

  factory InvoiceItem.fromMap(Map m) => InvoiceItem(
        sku: m['sku'],
        name: m['name'],
        qty: m['qty'],
        price: (m['price'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'sku': sku,
        'name': name,
        'qty': qty,
        'price': price,
        'total': qty * price,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Repositories
// ═════════════════════════════════════════════════════════════════════════════

/// Repository for client records.
class ClientRepository {
  final SecureStorageInterface _vault;
  ClientRepository(this._vault);

  Future<void> save(Client client) => _vault.secureSave(
        client.code,
        client.toMap(),
        sensitivity: SensitivityLevel.high,
        searchableText: client.searchText,
      );

  Future<Client?> getByCode(String code) async {
    final data = await _vault.secureGet<Map>(code);
    if (data == null) return null;
    return Client.fromMap(data.cast<String, dynamic>());
  }

  Future<List<Client>> search(String query) async {
    final results = await _vault.secureSearch<Map>(query);
    return results
        .map((m) => Client.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  Future<void> delete(String code) => _vault.secureDelete(code);

  Future<void> saveAll(List<Client> clients) => _vault.secureSaveBatch(
        {for (final c in clients) c.code: c.toMap()},
        sensitivity: SensitivityLevel.high,
      );
}

/// Repository for invoice records.
class InvoiceRepository {
  final SecureStorageInterface _vault;
  InvoiceRepository(this._vault);

  Future<void> save(Invoice invoice) => _vault.secureSave(
        invoice.number,
        invoice.toMap(),
        sensitivity: SensitivityLevel.high,
        searchableText: invoice.searchText,
      );

  Future<Invoice?> getByNumber(String number) async {
    final data = await _vault.secureGet<Map>(number);
    if (data == null) return null;
    return Invoice.fromMap(data.cast<String, dynamic>());
  }

  Future<List<Invoice>> search(String query) async {
    final results = await _vault.secureSearch<Map>(query);
    return results
        .map((m) => Invoice.fromMap(m.cast<String, dynamic>()))
        .toList();
  }

  Future<List<Invoice>> getByClient(String clientCode) async {
    return search(clientCode);
  }

  Future<void> updateStatus(String number, String status) async {
    final invoice = await getByNumber(number);
    if (invoice == null) return;
    final updated = Invoice(
      number: invoice.number,
      clientCode: invoice.clientCode,
      clientName: invoice.clientName,
      date: invoice.date,
      amount: invoice.amount,
      tax: invoice.tax,
      items: invoice.items,
      status: status,
    );
    await save(updated);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Main demo
// ═════════════════════════════════════════════════════════════════════════════

void main() async {
  print('╔════════════════════════════════════════════════════════════╗');
  print('║    HiveVault — ERP (gestion_commerciale_dz) Example        ║');
  print('╚════════════════════════════════════════════════════════════╝\n');

  final tempDir = await Directory.systemTemp.createTemp('erp_demo_');
  Hive.init(tempDir.path);

  // Open separate vaults for clients and invoices
  final clientVault = await HiveVault.create(
    boxName: 'clients',
    config: VaultConfig.debug(),
  );
  await clientVault.initialize();

  final invoiceVault = await HiveVault.create(
    boxName: 'invoices',
    config: VaultConfig.debug(),
  );
  await invoiceVault.initialize();

  final clients = ClientRepository(clientVault);
  final invoices = InvoiceRepository(invoiceVault);

  // ── Seed clients ────────────────────────────────────────────────────────
  print('▶ Seeding clients…');
  await clients.saveAll([
    const Client(
      code: 'CLI-001',
      name: 'Ahmed Mekraji',
      city: 'Constantine',
      phone: '+213 31 123456',
      email: 'ahmed@example.com',
      balance: 250000.0,
      taxId: '09123456789',
    ),
    const Client(
      code: 'CLI-002',
      name: 'Fatima Boudiaf',
      city: 'Algiers',
      phone: '+213 21 987654',
      email: 'fatima@example.com',
      balance: 180000.0,
      taxId: '09987654321',
    ),
    const Client(
      code: 'CLI-003',
      name: 'Karim Bouzid',
      city: 'Oran',
      phone: '+213 41 555666',
      email: 'karim@example.com',
      balance: 95000.0,
      taxId: '09555666777',
    ),
  ]);
  print('  ✅ 3 clients saved.\n');

  // ── Seed invoices ───────────────────────────────────────────────────────
  print('▶ Seeding invoices…');
  final invoiceList = [
    Invoice(
      number: 'INV-2026-001',
      clientCode: 'CLI-001',
      clientName: 'Ahmed Mekraji',
      date: DateTime(2026, 4, 16),
      amount: 125000.0,
      tax: 9.0,
      items: [
        const InvoiceItem(
            sku: 'LAPTOP', name: 'Laptop Pro', qty: 2, price: 55000),
        const InvoiceItem(
            sku: 'PRINT', name: 'Laser Printer', qty: 1, price: 15000),
      ],
      status: 'PENDING',
    ),
    Invoice(
      number: 'INV-2026-002',
      clientCode: 'CLI-002',
      clientName: 'Fatima Boudiaf',
      date: DateTime(2026, 4, 17),
      amount: 78500.0,
      tax: 9.0,
      items: [
        const InvoiceItem(
            sku: 'MONITOR', name: '4K Monitor', qty: 3, price: 22500),
      ],
      status: 'PAID',
    ),
    Invoice(
      number: 'INV-2026-003',
      clientCode: 'CLI-001',
      clientName: 'Ahmed Mekraji',
      date: DateTime(2026, 4, 18),
      amount: 34000.0,
      tax: 9.0,
      items: [
        const InvoiceItem(
            sku: 'KB', name: 'Wireless Keyboard', qty: 10, price: 2800),
      ],
      status: 'PENDING',
    ),
  ];

  for (final inv in invoiceList) {
    await invoices.save(inv);
  }
  print('  ✅ ${invoiceList.length} invoices saved.\n');

  // ── Queries ─────────────────────────────────────────────────────────────
  print('▶ Find client CLI-001:');
  final cli1 = await clients.getByCode('CLI-001');
  print('  Name: ${cli1?.name} | Balance: ${cli1?.balance} DZD');

  print('\n▶ Search clients in Constantine:');
  final constClients = await clients.search('Constantine');
  for (final c in constClients) {
    print('  ${c.code}: ${c.name}');
  }

  print('\n▶ All invoices for Ahmed (CLI-001):');
  final ahmedInvoices = await invoices.getByClient('CLI-001');
  for (final inv in ahmedInvoices) {
    print('  ${inv.number} — ${inv.amount} DZD — ${inv.status}');
  }

  print('\n▶ Update INV-2026-001 to PAID:');
  await invoices.updateStatus('INV-2026-001', 'PAID');
  final updated = await invoices.getByNumber('INV-2026-001');
  print('  Status is now: ${updated?.status}');

  print('\n▶ Search invoices by product "Laptop":');
  final laptopInvoices = await invoices.search('Laptop');
  print('  Found ${laptopInvoices.length} invoice(s).');

  // ── Stats ────────────────────────────────────────────────────────────────
  print('\n▶ Client vault stats:');
  print(await clientVault.getStats());

  print('▶ Invoice vault stats:');
  print(await invoiceVault.getStats());

  // ── Cleanup ──────────────────────────────────────────────────────────────
  await clientVault.close();
  await invoiceVault.close();
  await tempDir.delete(recursive: true);

  print('✅ ERP example completed successfully!');
}
