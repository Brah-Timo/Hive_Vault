// lib/src/impl/multi_box_vault.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Multi-box vault for module-level data isolation.
// ─────────────────────────────────────────────────────────────────────────────
//
// ERP systems typically have many data domains: clients, invoices, payslips,
// products, stock, etc. Each domain should have its own encrypted vault so
// that a breach in one domain does not expose others.
//
// MultiBoxVault manages a collection of named vaults and provides a unified
// API to route operations to the correct box automatically.
// ─────────────────────────────────────────────────────────────────────────────

import '../core/vault_config.dart';
import '../core/vault_interface.dart';
import '../core/vault_exceptions.dart';
import 'vault_factory.dart';

/// A collection of named HiveVault instances managed as a unit.
///
/// Each [boxName] gets its own encrypted box and index.
/// A single master config is shared across all boxes unless overridden.
///
/// ```dart
/// final erp = MultiBoxVault(
///   defaultConfig: VaultConfig.erp(),
///   modules: ['clients', 'invoices', 'products', 'payslips', 'settings'],
/// );
/// await erp.initialize();
///
/// final clientVault = erp['clients'];
/// await clientVault.secureSave('CLI-001', client.toMap());
///
/// final invoiceVault = erp.module('invoices');
/// final inv = await invoiceVault.secureGet<Map>('INV-001');
/// ```
class MultiBoxVault {
  final VaultConfig defaultConfig;
  final List<String> modules;
  final Map<String, VaultConfig> moduleConfigs;

  final Map<String, SecureStorageInterface> _vaults = {};

  MultiBoxVault({
    required this.defaultConfig,
    required this.modules,
    this.moduleConfigs = const {},
  });

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Opens all registered module vaults.
  Future<void> initialize() async {
    for (final name in modules) {
      final config = moduleConfigs[name] ?? defaultConfig;
      final vault = await HiveVault.open(boxName: name, config: config);
      _vaults[name] = vault;
    }
  }

  /// Closes all open vaults.
  Future<void> close() async {
    for (final vault in _vaults.values) {
      try {
        await vault.close();
      } catch (_) {}
    }
    _vaults.clear();
  }

  // ─── Access ───────────────────────────────────────────────────────────────

  /// Returns the vault for [moduleName].
  ///
  /// Throws [VaultInitException] if [moduleName] was not registered.
  SecureStorageInterface module(String moduleName) {
    final vault = _vaults[moduleName];
    if (vault == null) {
      throw VaultInitException(
        'Module "$moduleName" is not registered in MultiBoxVault. '
        'Add it to the modules list.',
      );
    }
    return vault;
  }

  /// Shorthand operator: `multiVault['clients']`.
  SecureStorageInterface operator [](String moduleName) => module(moduleName);

  /// Returns all registered module names.
  Iterable<String> get moduleNames => _vaults.keys;

  /// Returns `true` if [moduleName] is open and ready.
  bool isOpen(String moduleName) => _vaults.containsKey(moduleName);

  // ─── Cross-module search ──────────────────────────────────────────────────

  /// Searches across all modules and returns results grouped by module name.
  Future<Map<String, List<dynamic>>> searchAll(String query) async {
    final results = <String, List<dynamic>>{};
    for (final entry in _vaults.entries) {
      final found = await entry.value.secureSearch<dynamic>(query);
      if (found.isNotEmpty) {
        results[entry.key] = found;
      }
    }
    return results;
  }

  /// Closes and re-opens a single module vault.
  Future<void> reopen(String moduleName) async {
    final existing = _vaults[moduleName];
    await existing?.close();
    final config = moduleConfigs[moduleName] ?? defaultConfig;
    _vaults[moduleName] = await HiveVault.open(
      boxName: moduleName,
      config: config,
    );
  }
}
