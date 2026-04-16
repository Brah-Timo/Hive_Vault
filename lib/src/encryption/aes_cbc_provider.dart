// lib/src/encryption/aes_cbc_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — AES-256-CBC encryption provider + provider factory.
//
// Envelope layout:
//   [iv(16)] [ciphertext (PKCS7-padded)]
//
// Note: CBC does NOT include an authentication tag. If you need integrity
// verification use [AesGcmProvider]. CBC is provided for compatibility
// with systems that cannot use GCM.
// ─────────────────────────────────────────────────────────────────────────────

// All imports MUST come before any declarations (Dart requirement).
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import '../core/constants.dart';
import '../core/encryption_config.dart';
import '../core/sensitivity_level.dart';
import '../core/vault_exceptions.dart';
import 'aes_gcm_provider.dart';
import 'encryption_provider.dart';
import 'key_manager.dart';
import 'no_encryption_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AES-256-CBC provider
// ─────────────────────────────────────────────────────────────────────────────

/// AES-256-CBC encryption with random IV and PKCS7 padding.
///
/// Security properties:
/// - **Confidentiality**: AES-256 in CBC mode with PKCS7 padding.
/// - **No integrity check**: A corrupted or tampered ciphertext will produce
///   garbage plaintext silently. Use [AesGcmProvider] for integrity.
/// - **IV**: 16-byte random per call — same plaintext encrypts differently.
class AesCbcProvider extends EncryptionProvider {
  /// The 256-bit (32-byte) encryption key.
  final Uint8List key;

  AesCbcProvider({required this.key}) {
    if (key.length != kAesKeySize) {
      throw VaultConfigException(
        'AES-CBC key must be exactly $kAesKeySize bytes '
        '(got ${key.length})',
      );
    }
  }

  @override
  String get algorithmName => 'AES-256-CBC';

  @override
  int get headerFlag => EncryptionFlag.aesCbc;

  @override
  bool get supportsIntegrityCheck => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<Uint8List> encrypt(Uint8List plainData) async {
    try {
      // Generate a fresh 16-byte random IV.
      final iv = enc.IV.fromSecureRandom(kCbcIvSize);
      final encKey = enc.Key(key);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc));

      final encrypted = encrypter.encryptBytes(plainData, iv: iv);

      // Envelope: iv(16) + ciphertext
      final envelope = Uint8List(kCbcIvSize + encrypted.bytes.length);
      envelope.setRange(0, kCbcIvSize, iv.bytes);
      envelope.setRange(kCbcIvSize, envelope.length, encrypted.bytes);

      return envelope;
    } catch (e) {
      throw VaultEncryptionException('AES-256-CBC encryption failed', cause: e);
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData) async {
    if (encryptedData.length < kCbcIvSize) {
      throw VaultDecryptionException(
        'AES-256-CBC: encrypted data is too short '
        '(${encryptedData.length} bytes)',
      );
    }

    try {
      final ivBytes = encryptedData.sublist(0, kCbcIvSize);
      final cipherBytes = encryptedData.sublist(kCbcIvSize);

      final iv = enc.IV(ivBytes);
      final encKey = enc.Key(key);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc));

      final plainBytes = encrypter.decryptBytes(
        enc.Encrypted(cipherBytes),
        iv: iv,
      );

      return Uint8List.fromList(plainBytes);
    } catch (e) {
      throw VaultDecryptionException(
        'AES-256-CBC decryption failed — wrong key or corrupt data',
        cause: e,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory: instantiates the appropriate EncryptionProvider from config.
// ─────────────────────────────────────────────────────────────────────────────

/// Creates an [EncryptionProvider] from [config] and [masterKey].
///
/// [masterKey] is only used when encryption is enabled.
Future<EncryptionProvider> buildEncryptionProvider(
  EncryptionConfig config,
  Uint8List masterKey,
) async {
  switch (config.defaultSensitivity) {
    case SensitivityLevel.none:
      return const NoEncryptionProvider();

    case SensitivityLevel.standard:
      // CBC: use master key directly (no PBKDF2 per-call derivation).
      // For stronger security consider upgrading to GCM.
      return AesCbcProvider(key: masterKey);

    case SensitivityLevel.high:
    case SensitivityLevel.selective:
      // GCM with per-call PBKDF2 derivation.
      return AesGcmProvider(
        masterKey: masterKey,
        pbkdf2Iterations: config.pbkdf2Iterations,
      );
  }
}
