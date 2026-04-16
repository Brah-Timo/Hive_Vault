// lib/src/encryption/encryption_factory.dart
//
// HiveVault — Resolves [EncryptionProvider] from config + master key.

import 'dart:typed_data';

import '../core/vault_exceptions.dart';
import 'encryption_config.dart';
import 'encryption_provider.dart';
import 'sensitivity_level.dart';
import 'aes_gcm_provider.dart';
import 'aes_cbc_provider.dart';
import 'no_encryption_provider.dart';

/// Creates the correct [EncryptionProvider] based on [SensitivityLevel]
/// and a 256-bit [masterKey].
class EncryptionFactory {
  const EncryptionFactory._();

  /// Resolve a provider for the [config]'s [defaultSensitivity].
  static EncryptionProvider create(
    EncryptionConfig config,
    Uint8List masterKey,
  ) {
    return forLevel(config.defaultSensitivity, masterKey,
        iterations: config.pbkdf2Iterations);
  }

  /// Resolve a provider for an explicit [level].
  static EncryptionProvider forLevel(
    SensitivityLevel level,
    Uint8List masterKey, {
    int iterations = 100000,
  }) {
    switch (level) {
      case SensitivityLevel.none:
        return const NoEncryptionProvider();

      case SensitivityLevel.standard:
        return AesCbcEncryptionProvider(masterKey: masterKey);

      case SensitivityLevel.high:
      case SensitivityLevel.selective:
        return AesGcmEncryptionProvider(
          masterKey: masterKey,
          pbkdf2Iterations: iterations,
        );
    }
    // ignore: dead_code
    throw VaultConfigException(
      'Unknown SensitivityLevel: $level',
    );
  }
}
