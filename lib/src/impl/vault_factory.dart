// lib/src/impl/vault_factory.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Top-level factory / entry-point for creating vault instances.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/vault_config.dart';
import '../core/vault_interface.dart';
import '../core/constants.dart';
import '../core/sensitivity_level.dart';
import '../compression/auto_compression_provider.dart';
import '../encryption/aes_cbc_provider.dart' show buildEncryptionProvider;
import '../encryption/key_manager.dart';
import 'hive_vault_impl.dart';

/// The public entry-point for creating [HiveVaultImpl] instances.
///
/// ```dart
/// final vault = await HiveVault.create(
///   boxName: 'invoices',
///   config: VaultConfig.erp(),
/// );
/// await vault.initialize();
/// ```
///
/// Or as a one-liner (includes initialisation):
///
/// ```dart
/// final vault = await HiveVault.open(
///   boxName: 'invoices',
///   config: VaultConfig.erp(),
/// );
/// ```
class HiveVault {
  HiveVault._(); // Not instantiable — static factory only.

  // ─── Hive initialisation ──────────────────────────────────────────────────

  /// Initialises Hive for Flutter applications. Call once from `main()`.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await HiveVault.initHive();
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> initHive() => Hive.initFlutter();

  // ─── Factory methods ──────────────────────────────────────────────────────

  /// Creates a new vault with [config] and opens + initialises it immediately.
  ///
  /// Parameters:
  /// - [boxName]   Name of the underlying Hive box.
  /// - [config]    Vault configuration (defaults to [VaultConfig.erp]).
  /// - [masterKey] Optional pre-existing master key. If `null` the key is
  ///               retrieved from secure storage or generated automatically.
  ///
  /// Throws [VaultInitException] if the box cannot be opened.
  /// Throws [VaultKeyException] if key management fails.
  static Future<SecureStorageInterface> open({
    required String boxName,
    VaultConfig? config,
    Uint8List? masterKey,
  }) async {
    final effective = config ?? VaultConfig.erp();
    final vault = await create(
      boxName: boxName,
      config: effective,
      masterKey: masterKey,
    );
    await vault.initialize();
    return vault;
  }

  /// Creates a [HiveVaultImpl] without initialising it.
  ///
  /// Call [SecureStorageInterface.initialize] before any other method.
  static Future<HiveVaultImpl> create({
    required String boxName,
    VaultConfig? config,
    Uint8List? masterKey,
  }) async {
    final effective = config ?? VaultConfig.erp();

    // Resolve master key.
    Uint8List resolvedKey;
    if (effective.encryption.defaultSensitivity != SensitivityLevel.none) {
      resolvedKey = masterKey ??
          await KeyManager.getOrCreateMasterKey(kMasterKeyStorageId);
      await KeyManager.storeKeyCreationDate(kMasterKeyStorageId);
    } else {
      resolvedKey = Uint8List(kAesKeySize); // zero key, unused
    }

    // Build providers.
    final compressor = buildCompressionProvider(effective.compression);
    final encryptor = await buildEncryptionProvider(
      effective.encryption,
      resolvedKey,
    );

    return HiveVaultImpl(
      boxName: boxName,
      config: effective,
      compressor: compressor,
      encryptor: encryptor,
    );
  }

  // ─── Multiple vault management ────────────────────────────────────────────

  static final Map<String, SecureStorageInterface> _registry = {};

  /// Returns a named vault from the registry, or creates and registers a new
  /// one if it does not exist yet.
  ///
  /// Useful when multiple parts of your app share the same vault instance.
  static Future<SecureStorageInterface> getOrOpen({
    required String boxName,
    VaultConfig? config,
  }) async {
    if (_registry.containsKey(boxName)) {
      return _registry[boxName]!;
    }
    final vault = await open(boxName: boxName, config: config);
    _registry[boxName] = vault;
    return vault;
  }

  /// Closes and removes a vault from the registry.
  static Future<void> closeVault(String boxName) async {
    final vault = _registry.remove(boxName);
    await vault?.close();
  }

  /// Closes all registered vaults. Call from your app's dispose lifecycle.
  static Future<void> closeAll() async {
    for (final vault in _registry.values) {
      try {
        await vault.close();
      } catch (_) {
        // Best-effort close.
      }
    }
    _registry.clear();
  }

  // ─── Key rotation helper ──────────────────────────────────────────────────

  /// Performs a full key rotation on an open [vault]:
  /// 1. Exports all data with the old key.
  /// 2. Generates a new master key.
  /// 3. Re-imports all data with the new key.
  /// 4. Commits the rotation.
  ///
  /// ⚠️  The vault is temporarily in an inconsistent state during rotation.
  ///     Keep a backup before calling this in production.
  static Future<void> rotateKey(
    SecureStorageInterface vault,
    String boxName,
  ) async {
    // Export
    final archive = await vault.exportEncrypted();

    // Rotate key in secure storage
    final rotation = await KeyManager.rotateKey(kMasterKeyStorageId);

    try {
      // Re-open with new key (old vault instance stays alive for rollback)
      final newVault = await open(
        boxName: '${boxName}_rotated',
        masterKey: rotation.newKey,
      );

      // Import old data into new vault
      await newVault.importEncrypted(archive);

      // Commit
      await KeyManager.commitRotation(rotation);

      // Log success
    } catch (e) {
      await KeyManager.abortRotation(rotation);
      rethrow;
    }
  }
}
