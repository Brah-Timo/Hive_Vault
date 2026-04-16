// lib/src/core/vault_exceptions.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Custom exception hierarchy.
// ─────────────────────────────────────────────────────────────────────────────

/// Base exception for all HiveVault errors.
abstract class VaultException implements Exception {
  const VaultException(this.message, {this.cause});

  /// Human-readable description of the error.
  final String message;

  /// The underlying exception that caused this error (if any).
  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'VaultException: $message\n  Caused by: $cause';
    return 'VaultException: $message';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Encryption exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when encryption fails.
class VaultEncryptionException extends VaultException {
  const VaultEncryptionException(super.message, {super.cause});

  @override
  String toString() => 'VaultEncryptionException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when decryption fails (wrong key, corrupted data, bad tag, …).
class VaultDecryptionException extends VaultException {
  const VaultDecryptionException(super.message, {super.cause});

  @override
  String toString() => 'VaultDecryptionException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when GCM integrity verification fails — data may have been tampered.
class VaultIntegrityException extends VaultException {
  const VaultIntegrityException(super.message, {super.cause});

  @override
  String toString() => 'VaultIntegrityException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when key derivation or key management fails.
class VaultKeyException extends VaultException {
  const VaultKeyException(super.message, {super.cause});

  @override
  String toString() => 'VaultKeyException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Compression exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when compression fails.
class VaultCompressionException extends VaultException {
  const VaultCompressionException(super.message, {super.cause});

  @override
  String toString() => 'VaultCompressionException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when decompression fails (corrupted compressed data).
class VaultDecompressionException extends VaultException {
  const VaultDecompressionException(super.message, {super.cause});

  @override
  String toString() => 'VaultDecompressionException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage / IO exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the underlying Hive box cannot be opened.
class VaultInitException extends VaultException {
  const VaultInitException(super.message, {super.cause});

  @override
  String toString() => 'VaultInitException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when a storage read or write operation fails.
class VaultStorageException extends VaultException {
  const VaultStorageException(super.message, {super.cause});

  @override
  String toString() => 'VaultStorageException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when a payload has an unrecognised version or is malformed.
class VaultPayloadException extends VaultException {
  const VaultPayloadException(super.message, {super.cause});

  @override
  String toString() => 'VaultPayloadException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when an invalid configuration value is provided.
class VaultConfigException extends VaultException {
  const VaultConfigException(super.message, {super.cause});

  @override
  String toString() => 'VaultConfigException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Import / Export exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when export serialisation fails.
class VaultExportException extends VaultException {
  const VaultExportException(super.message, {super.cause});

  @override
  String toString() => 'VaultExportException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}

/// Thrown when import deserialisation or validation fails.
class VaultImportException extends VaultException {
  const VaultImportException(super.message, {super.cause});

  @override
  String toString() => 'VaultImportException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}
