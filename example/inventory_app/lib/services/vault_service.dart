// example/inventory_app/lib/services/vault_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Initialises and provides all HiveVault instances for the app.
//
// Compression strategy:
//   Native (Android / iOS / desktop) → GZip for large datasets
//   Web                              → Lz4 (pure Dart, no dart:io dependency)
//
// All seven vaults are opened in parallel for fast startup.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_vault/hive_vault.dart';

/// Named box identifiers for each HiveVault instance.
class AppVaults {
  static const products = 'inv_products';
  static const categories = 'inv_categories';
  static const movements = 'inv_movements';
  static const suppliers = 'inv_suppliers';
  static const orders = 'inv_orders';
  static const alerts = 'inv_alerts';
  static const settings = 'inv_settings';
}

/// Centralised singleton that owns all HiveVault instances.
class VaultService {
  static VaultService? _instance;

  late final HiveVaultImpl productsVault;
  late final HiveVaultImpl categoriesVault;
  late final HiveVaultImpl movementsVault;
  late final HiveVaultImpl suppliersVault;
  late final HiveVaultImpl ordersVault;
  late final HiveVaultImpl alertsVault;
  late final HiveVaultImpl settingsVault;

  bool _initialized = false;

  VaultService._();
  factory VaultService() => _instance ??= VaultService._();

  // ── Platform helpers ─────────────────────────────────────────────────────

  /// On Web, dart:io codecs (GZip/Deflate) are unavailable. We use Lz4 (pure
  /// Dart) as the compression strategy so all platforms work identically.
  static CompressionStrategy get _compression =>
      kIsWeb ? CompressionStrategy.lz4 : CompressionStrategy.gzip;

  // ── Public API ───────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    await HiveVault.initHive();

    // ── Product vault: full-featured (encryption + compression + indexing) ──
    productsVault = await HiveVault.create(
      boxName: AppVaults.products,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          gzipLevel: 6,
          minimumSizeForCompression: 128,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.high,
          pbkdf2Iterations: 100000,
          enableIntegrityCheck: true,
        ),
        indexing: const IndexingConfig(
          enableAutoIndexing: true,
          minimumTokenLength: 2,
          enablePrefixSearch: true,
          buildIndexInBackground: true,
        ),
        enableAuditLog: true,
        enableIntegrityChecks: true,
        memoryCacheSize: 200,
      ),
    );

    // ── Categories vault: light config (small dataset) ───────────────────
    categoriesVault = await HiveVault.create(
      boxName: AppVaults.categories,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          minimumSizeForCompression: 256,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.standard,
          pbkdf2Iterations: 50000,
          enableIntegrityCheck: false,
        ),
        indexing: const IndexingConfig.disabled(),
        enableAuditLog: false,
        enableIntegrityChecks: false,
        enableBackgroundProcessing: false,
        memoryCacheSize: 30,
      ),
    );

    // ── Stock movements vault: large dataset, compress aggressively ───────
    movementsVault = await HiveVault.create(
      boxName: AppVaults.movements,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          gzipLevel: 6,
          minimumSizeForCompression: 64,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.standard,
        ),
        indexing: const IndexingConfig(
          enableAutoIndexing: false,
        ),
        enableAuditLog: false,
        memoryCacheSize: 100,
      ),
    );

    // ── Suppliers vault: standard encryption ─────────────────────────────
    suppliersVault = await HiveVault.create(
      boxName: AppVaults.suppliers,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          gzipLevel: 6,
          minimumSizeForCompression: 128,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.high,
          pbkdf2Iterations: 100000,
          enableIntegrityCheck: true,
        ),
        indexing: const IndexingConfig(
          enableAutoIndexing: true,
          minimumTokenLength: 2,
          enablePrefixSearch: true,
          buildIndexInBackground: true,
        ),
        enableAuditLog: true,
        enableIntegrityChecks: true,
        memoryCacheSize: 200,
      ),
    );

    // ── Purchase orders vault: full audit trail ───────────────────────────
    ordersVault = await HiveVault.create(
      boxName: AppVaults.orders,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          gzipLevel: 6,
          minimumSizeForCompression: 128,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.high,
          pbkdf2Iterations: 100000,
          enableIntegrityCheck: true,
        ),
        indexing: const IndexingConfig(
          enableAutoIndexing: true,
          minimumTokenLength: 2,
          enablePrefixSearch: true,
          buildIndexInBackground: true,
        ),
        enableAuditLog: true,
        enableIntegrityChecks: true,
        memoryCacheSize: 200,
      ),
    );

    // ── Alerts vault: fast reads, minimal overhead ────────────────────────
    alertsVault = await HiveVault.create(
      boxName: AppVaults.alerts,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          minimumSizeForCompression: 256,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.standard,
          pbkdf2Iterations: 50000,
          enableIntegrityCheck: false,
        ),
        indexing: const IndexingConfig.disabled(),
        enableAuditLog: false,
        enableIntegrityChecks: false,
        enableBackgroundProcessing: false,
        memoryCacheSize: 30,
      ),
    );

    // ── Settings vault: max security (user prefs, tokens) ────────────────
    settingsVault = await HiveVault.create(
      boxName: AppVaults.settings,
      config: VaultConfig(
        compression: CompressionConfig(
          strategy: _compression,
          gzipLevel: kIsWeb ? 6 : 9,
          minimumSizeForCompression: 32,
        ),
        encryption: const EncryptionConfig(
          defaultSensitivity: SensitivityLevel.high,
          pbkdf2Iterations: 200000,
          enableIntegrityCheck: true,
        ),
        indexing: const IndexingConfig.full(),
        enableAuditLog: true,
        enableIntegrityChecks: true,
        memoryCacheSize: 50,
      ),
    );

    // Initialise all vaults in parallel.
    await Future.wait([
      productsVault.initialize(),
      categoriesVault.initialize(),
      movementsVault.initialize(),
      suppliersVault.initialize(),
      ordersVault.initialize(),
      alertsVault.initialize(),
      settingsVault.initialize(),
    ]);

    _initialized = true;
  }

  Future<void> closeAll() async {
    if (!_initialized) return;
    await Future.wait([
      productsVault.close(),
      categoriesVault.close(),
      movementsVault.close(),
      suppliersVault.close(),
      ordersVault.close(),
      alertsVault.close(),
      settingsVault.close(),
    ]);
    _initialized = false;
    _instance = null;
  }

  Future<VaultStats> getCombinedStats() async => productsVault.getStats();
}
