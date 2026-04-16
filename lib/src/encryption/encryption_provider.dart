// lib/src/encryption/encryption_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Abstract interface for all encryption providers.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

/// Contract that every encryption algorithm must satisfy.
///
/// Both [encrypt] and [decrypt] are async because real-world key derivation
/// (PBKDF2) and authenticated encryption (AES-GCM) involve async primitives
/// in the `cryptography` package.
abstract class EncryptionProvider {
  // Const constructor so that subclasses can declare `const` constructors
  // while using `extends` (which requires the super-constructor to be const).
  const EncryptionProvider();

  /// Algorithm name used in statistics and audit logs (e.g. "AES-256-GCM").
  String get algorithmName;

  /// Integer flag written into the binary payload header.
  /// Must match one of the [EncryptionFlag] constants.
  int get headerFlag;

  /// Whether this provider uses authenticated encryption (e.g. AES-GCM).
  /// When `true` any modification to the ciphertext is detected on decrypt.
  bool get supportsIntegrityCheck;

  /// Encrypts [plainData] and returns the full ciphertext envelope
  /// (nonce/IV + ciphertext + tag if applicable).
  ///
  /// The returned bytes are self-contained: no external IV or tag storage
  /// is required.
  ///
  /// Throws [VaultEncryptionException] on failure.
  Future<Uint8List> encrypt(Uint8List plainData);

  /// Decrypts [encryptedData] produced by [encrypt] and returns the
  /// original plaintext bytes.
  ///
  /// Throws [VaultDecryptionException] if decryption fails.
  /// Throws [VaultIntegrityException] if the authentication tag is invalid
  /// (only relevant when [supportsIntegrityCheck] is `true`).
  Future<Uint8List> decrypt(Uint8List encryptedData);

  /// Releases any resources held by this provider (key material, etc.).
  /// Must be called when the vault is closed.
  Future<void> dispose() async {}
}
