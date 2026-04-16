// lib/src/core/encryption_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Encryption configuration.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';
import 'sensitivity_level.dart';

/// Immutable configuration for the encryption layer.
@immutable
class EncryptionConfig {
  /// Default sensitivity level applied when none is specified per-call.
  final SensitivityLevel defaultSensitivity;

  /// Number of PBKDF2-HMAC-SHA256 iterations for key derivation.
  /// Higher = slower key derivation but more resistance to brute-force.
  /// OWASP recommends ≥ 600,000 for SHA-1; 100,000 is a reasonable minimum
  /// for SHA-256 on mobile hardware.
  final int pbkdf2Iterations;

  /// Whether to enable GCM integrity verification on read.
  /// Disabling this skips the authentication tag check (not recommended).
  final bool enableIntegrityCheck;

  /// Whether selective (field-level) encryption is supported.
  final bool enableSelectiveEncryption;

  /// Set of field names that are encrypted in [SensitivityLevel.selective] mode.
  final Set<String> sensitiveFields;

  /// Whether automatic key rotation is enabled.
  final bool enableKeyRotation;

  /// Rotation period in days. After this many days the vault prompts a
  /// key rotation on next open.
  final int keyRotationDays;

  const EncryptionConfig({
    this.defaultSensitivity = SensitivityLevel.high,
    this.pbkdf2Iterations = 100000,
    this.enableIntegrityCheck = true,
    this.enableSelectiveEncryption = false,
    this.sensitiveFields = const {},
    this.enableKeyRotation = false,
    this.keyRotationDays = 90,
  }) : assert(
          pbkdf2Iterations >= 1000,
          'pbkdf2Iterations must be at least 1000',
        );

  // ─── Predefined presets ──────────────────────────────────────────────────

  /// Maximum security: GCM + integrity + 200k PBKDF2 rounds.
  const EncryptionConfig.maxSecurity()
      : this(
          defaultSensitivity: SensitivityLevel.high,
          pbkdf2Iterations: 200000,
          enableIntegrityCheck: true,
          enableKeyRotation: true,
          keyRotationDays: 30,
        );

  /// Standard security: CBC + 100k rounds, no integrity tag.
  const EncryptionConfig.standard()
      : this(
          defaultSensitivity: SensitivityLevel.standard,
          pbkdf2Iterations: 100000,
          enableIntegrityCheck: false,
        );

  /// No encryption — development/debug only. Never use in production.
  const EncryptionConfig.disabled()
      : this(
          defaultSensitivity: SensitivityLevel.none,
          pbkdf2Iterations: 1000,
          enableIntegrityCheck: false,
        );

  // ─── Equality & copy ─────────────────────────────────────────────────────

  EncryptionConfig copyWith({
    SensitivityLevel? defaultSensitivity,
    int? pbkdf2Iterations,
    bool? enableIntegrityCheck,
    bool? enableSelectiveEncryption,
    Set<String>? sensitiveFields,
    bool? enableKeyRotation,
    int? keyRotationDays,
  }) {
    return EncryptionConfig(
      defaultSensitivity: defaultSensitivity ?? this.defaultSensitivity,
      pbkdf2Iterations: pbkdf2Iterations ?? this.pbkdf2Iterations,
      enableIntegrityCheck: enableIntegrityCheck ?? this.enableIntegrityCheck,
      enableSelectiveEncryption:
          enableSelectiveEncryption ?? this.enableSelectiveEncryption,
      sensitiveFields: sensitiveFields ?? this.sensitiveFields,
      enableKeyRotation: enableKeyRotation ?? this.enableKeyRotation,
      keyRotationDays: keyRotationDays ?? this.keyRotationDays,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptionConfig &&
          defaultSensitivity == other.defaultSensitivity &&
          pbkdf2Iterations == other.pbkdf2Iterations &&
          enableIntegrityCheck == other.enableIntegrityCheck &&
          enableSelectiveEncryption == other.enableSelectiveEncryption &&
          enableKeyRotation == other.enableKeyRotation &&
          keyRotationDays == other.keyRotationDays;

  @override
  int get hashCode => Object.hash(
        defaultSensitivity,
        pbkdf2Iterations,
        enableIntegrityCheck,
        enableSelectiveEncryption,
        enableKeyRotation,
        keyRotationDays,
      );

  @override
  String toString() => 'EncryptionConfig('
      'sensitivity: ${defaultSensitivity.label}, '
      'iterations: $pbkdf2Iterations, '
      'integrity: $enableIntegrityCheck)';
}
