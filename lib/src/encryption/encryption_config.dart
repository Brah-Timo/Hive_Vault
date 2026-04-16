// lib/src/encryption/encryption_config.dart

import 'package:meta/meta.dart';
import 'sensitivity_level.dart';

/// Encryption settings carried inside [VaultConfig].
@immutable
class EncryptionConfig {
  const EncryptionConfig({
    this.defaultSensitivity = SensitivityLevel.high,
    this.pbkdf2Iterations = 100000,
    this.enableSelectiveEncryption = false,
    this.sensitiveFields = const {},
    this.enableIntegrityCheck = true,
    this.enableKeyRotation = false,
    this.keyRotationDays = 90,
  });

  /// Default [SensitivityLevel] applied when [secureSave] is called without
  /// an explicit [sensitivity] override.
  final SensitivityLevel defaultSensitivity;

  /// Number of PBKDF2-HMAC-SHA256 iterations used to derive a per-entry key
  /// from the master key + random salt.
  ///
  /// Higher = slower brute-force, but slower save.
  /// NIST recommends ≥ 600,000 for passwords; 100,000 is a pragmatic balance
  /// for device-local data where the master key is 256 random bits.
  final int pbkdf2Iterations;

  /// When `true`, the [sensitiveFields] list is consulted to apply higher-
  /// sensitivity encryption to specific map keys automatically.
  final bool enableSelectiveEncryption;

  /// Map keys that should automatically receive [SensitivityLevel.high]
  /// treatment even when the caller did not specify one.
  final Set<String> sensitiveFields;

  /// When `true`, AES-GCM authentication tags are verified on every read.
  /// Disable only in [VaultConfig.debug] or performance benchmarks.
  final bool enableIntegrityCheck;

  /// When `true`, the master key is rotated every [keyRotationDays] days.
  final bool enableKeyRotation;

  /// Days between automatic key rotations (only relevant when
  /// [enableKeyRotation] is `true`).
  final int keyRotationDays;

  @override
  String toString() =>
      'EncryptionConfig(sensitivity=${defaultSensitivity.name}, '
      'iterations=$pbkdf2Iterations, integrity=$enableIntegrityCheck)';
}
