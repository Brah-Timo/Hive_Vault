# Multi-Box Vault

> **File**: `lib/src/impl/multi_box_vault.dart`

`MultiBoxVault` manages a collection of named `SecureStorageInterface` instances (vaults) as a single unit, providing domain-level data isolation for complex applications like ERP systems.

---

## Why Multi-Box?

| Concern | Solution |
|---|---|
| A breach in one module should not expose others | Each module has its own encrypted box |
| Different modules have different security/perf needs | Per-module `VaultConfig` |
| Cross-module search is needed | `searchAll()` method |
| Domain data should be physically separate | Each module is a separate Hive box |

---

## `MultiBoxVault`

```dart
class MultiBoxVault {
  final VaultConfig defaultConfig;
  final List<String> modules;                        // Module names
  final Map<String, VaultConfig> moduleConfigs;      // Per-module overrides

  final Map<String, SecureStorageInterface> _vaults = {};

  MultiBoxVault({
    required this.defaultConfig,
    required this.modules,
    this.moduleConfigs = const {},
  });
}
```

---

## Lifecycle

```dart
// Opens all registered module vaults
await multiVault.initialize();

// Closes all open vaults
await multiVault.close();
```

---

## Accessing Module Vaults

```dart
// By name (throws VaultInitException if not registered)
SecureStorageInterface clients  = multiVault.module('clients');
SecureStorageInterface invoices = multiVault['invoices'];   // [] operator

// Check registration
bool open = multiVault.isOpen('products');

// All module names
Iterable<String> names = multiVault.moduleNames;
```

---

## Cross-Module Search

```dart
Map<String, List<dynamic>> results = await multiVault.searchAll('acme');
// Returns:
// {
//   'clients': [{'name': 'ACME Corp', ...}],
//   'invoices': [{'client': 'ACME Corp', 'total': 5000}, ...]
// }
```

Search runs in parallel across all modules. Modules with no results are omitted from the return value.

---

## Module Reopen

```dart
// Close and re-open a single module (e.g., after key rotation)
await multiVault.reopen('payslips');
```

---

## Setup Example (ERP)

```dart
final erp = MultiBoxVault(
  defaultConfig: VaultConfig.erp(),
  modules: [
    'clients',
    'suppliers',
    'products',
    'invoices',
    'purchase_orders',
    'payslips',
    'settings',
    'audit_archive',
  ],
  moduleConfigs: {
    // Settings: lightweight — no heavy encryption needed
    'settings': VaultConfig.light(),

    // Payslips: maximum security — GDPR / payroll data
    'payslips': VaultConfig.maxSecurity(),

    // Audit archive: no compression needed (already text), large cache
    'audit_archive': VaultConfig.erp().copyWith(
      memoryCacheSize: 50,
      compression: CompressionConfig(strategy: CompressionStrategy.none),
    ),
  },
);

await erp.initialize();

// Use individual modules
await erp['clients'].secureSave('CLI-001', clientData);
final invoice = await erp.module('invoices').secureGet<Map>('INV-001');

// Cross-module search
final hits = await erp.searchAll('john smith');
```

---

## Module Vault Config Inheritance

If a module is listed in `modules` but NOT in `moduleConfigs`, it uses `defaultConfig`. If listed in `moduleConfigs`, the per-module config overrides the default for that module only.

```dart
MultiBoxVault(
  defaultConfig: VaultConfig.erp(),       // Used for: clients, invoices, products
  modules: ['clients', 'invoices', 'products', 'settings'],
  moduleConfigs: {
    'settings': VaultConfig.light(),      // Only settings uses light config
  },
)
```

---

## `module()` Error Handling

```dart
try {
  final vault = multiVault.module('unknown');
} on VaultInitException catch (e) {
  print(e.message);
  // 'Module "unknown" is not registered in MultiBoxVault.
  //  Add it to the modules list.'
}
```
