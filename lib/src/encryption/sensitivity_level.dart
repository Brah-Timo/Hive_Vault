// lib/src/encryption/sensitivity_level.dart

/// Controls how (and whether) a stored entry is encrypted.
///
/// The integer [index] of each variant is embedded directly in the
/// payload header so the correct cipher is selected at read time.
enum SensitivityLevel {
  /// No encryption — plain (optionally compressed) bytes are stored.
  /// Use only for public / non-sensitive data.
  none, // index = 0

  /// AES-256-CBC — classic cipher, no authentication tag.
  /// Adequate for general private data.
  standard, // index = 1

  /// AES-256-GCM — authenticated encryption with integrity guarantee.
  /// Use for financial data, PII, payroll, and any secret that must not
  /// be silently tampered with.
  high, // index = 2

  /// Field-level selective encryption.
  /// The caller is responsible for splitting public and sensitive fields
  /// into separate [secureSave] calls with different [SensitivityLevel]s.
  selective, // index = 3
}
