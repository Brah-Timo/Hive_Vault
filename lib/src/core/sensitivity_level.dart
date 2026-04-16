// lib/src/core/sensitivity_level.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Data sensitivity levels that drive encryption behaviour.
// ─────────────────────────────────────────────────────────────────────────────

/// Defines how sensitive a piece of data is, controlling which encryption
/// algorithm (if any) is applied to it.
enum SensitivityLevel {
  /// No encryption is applied. Suitable for non-sensitive cached data
  /// or development/debug builds.
  none,

  /// Standard AES-256-CBC encryption. Provides confidentiality without
  /// authenticated encryption. Suitable for moderately sensitive data.
  standard,

  /// AES-256-GCM encryption with authenticated integrity verification.
  /// Use for financial records, personal data, passwords, salaries, etc.
  high,

  /// Field-level selective encryption where only explicitly marked fields
  /// inside the object are encrypted; the rest is stored in plaintext.
  /// Useful when parts of a record must remain searchable.
  selective,
}

/// Extension helpers for [SensitivityLevel].
extension SensitivityLevelX on SensitivityLevel {
  /// Returns `true` if any form of encryption is required.
  bool get requiresEncryption => this != SensitivityLevel.none;

  /// Returns `true` if GCM authenticated encryption is required.
  bool get requiresAuthenticatedEncryption => this == SensitivityLevel.high;

  /// Human-readable label for logging and debugging.
  String get label {
    switch (this) {
      case SensitivityLevel.none:
        return 'None';
      case SensitivityLevel.standard:
        return 'Standard (AES-256-CBC)';
      case SensitivityLevel.high:
        return 'High (AES-256-GCM)';
      case SensitivityLevel.selective:
        return 'Selective (Field-Level)';
    }
  }
}
