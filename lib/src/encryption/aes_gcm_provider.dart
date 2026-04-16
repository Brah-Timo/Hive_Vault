// lib/src/encryption/aes_gcm_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — AES-256-GCM authenticated encryption provider.
//
// Envelope layout (all lengths are bytes):
//   [salt(16)] [nonce(12)] [ciphertext + GCM_tag(16)]
//
// The GCM tag is appended by the `cryptography` package to the ciphertext.
// Salt is used to derive a per-session sub-key via PBKDF2-HMAC-SHA256,
// preventing key-reuse attacks even if the same master key is used many times.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;
import '../core/constants.dart';
import '../core/vault_exceptions.dart';
import 'encryption_provider.dart';
import 'key_manager.dart';

/// AES-256-GCM authenticated encryption with PBKDF2 key derivation.
///
/// Security properties:
/// - **Confidentiality**: AES-256 in GCM mode.
/// - **Integrity + Authenticity**: 128-bit GCM tag — any bit flip in the
///   ciphertext causes decryption to fail.
/// - **Key derivation**: PBKDF2-HMAC-SHA256 with a fresh 16-byte salt per
///   encryption call — even if two calls encrypt identical plaintext, the
///   output will be different.
/// - **Nonce**: 12-byte random nonce per call (never reused for the same key).
class AesGcmProvider extends EncryptionProvider {
  /// The 256-bit master key used for key derivation.
  final Uint8List masterKey;

  /// PBKDF2 iteration count.
  final int pbkdf2Iterations;

  const AesGcmProvider({
    required this.masterKey,
    this.pbkdf2Iterations = kDefaultPbkdf2Iterations,
  });

  @override
  String get algorithmName => 'AES-256-GCM';

  @override
  int get headerFlag => EncryptionFlag.aesGcm;

  @override
  bool get supportsIntegrityCheck => true;

  @override
  Future<void> dispose() async {}

  // Envelope offsets.
  static const int _saltStart = 0;
  static const int _saltEnd = kSaltSize; // 16
  static const int _nonceStart = _saltEnd;
  static const int _nonceEnd = _nonceStart + kGcmNonceSize; // 28
  static const int _dataStart = _nonceEnd; // 28

  @override
  Future<Uint8List> encrypt(Uint8List plainData) async {
    try {
      // 1. Fresh random salt and nonce.
      final salt = KeyManager.generateRandom(kSaltSize);
      final nonce = KeyManager.generateRandom(kGcmNonceSize);

      // 2. Derive a 256-bit sub-key from master key + salt.
      final derivedKey = await KeyManager.deriveKeyFromPassword(
        password: String.fromCharCodes(masterKey),
        salt: salt,
        iterations: pbkdf2Iterations,
      );

      // 3. Encrypt with AES-256-GCM.
      final algorithm = crypto.AesGcm.with256bits(nonceLength: kGcmNonceSize);
      final secretKey = await algorithm.newSecretKeyFromBytes(derivedKey);
      final secretBox = await algorithm.encrypt(
        plainData,
        secretKey: secretKey,
        nonce: nonce,
      );

      // 4. Assemble envelope: salt + nonce + ciphertext+tag.
      final cipherAndTag = Uint8List.fromList(
        [...secretBox.cipherText, ...secretBox.mac.bytes],
      );
      final envelope = Uint8List(kSaltSize + kGcmNonceSize + cipherAndTag.length);
      envelope.setRange(_saltStart, _saltEnd, salt);
      envelope.setRange(_nonceStart, _nonceEnd, nonce);
      envelope.setRange(_dataStart, envelope.length, cipherAndTag);

      return envelope;
    } on VaultKeyException {
      rethrow;
    } catch (e) {
      throw VaultEncryptionException(
        'AES-256-GCM encryption failed',
        cause: e,
      );
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData) async {
    if (encryptedData.length < _dataStart + kGcmTagSize) {
      throw VaultDecryptionException(
        'AES-256-GCM: encrypted data is too short '
        '(${encryptedData.length} bytes)',
      );
    }

    try {
      // 1. Extract components.
      final salt = encryptedData.sublist(_saltStart, _saltEnd);
      final nonce = encryptedData.sublist(_nonceStart, _nonceEnd);
      final cipherAndTag = encryptedData.sublist(_dataStart);

      // Split ciphertext and GCM tag.
      final cipherText =
          cipherAndTag.sublist(0, cipherAndTag.length - kGcmTagSize);
      final tag =
          cipherAndTag.sublist(cipherAndTag.length - kGcmTagSize);

      // 2. Derive the same sub-key.
      final derivedKey = await KeyManager.deriveKeyFromPassword(
        password: String.fromCharCodes(masterKey),
        salt: salt,
        iterations: pbkdf2Iterations,
      );

      // 3. Decrypt and verify integrity.
      final algorithm = crypto.AesGcm.with256bits(nonceLength: kGcmNonceSize);
      final secretKey = await algorithm.newSecretKeyFromBytes(derivedKey);
      final secretBox = crypto.SecretBox(
        cipherText,
        nonce: nonce,
        mac: crypto.Mac(tag),
      );

      final plainText = await algorithm.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(plainText);
    } on crypto.SecretBoxAuthenticationError {
      throw VaultIntegrityException(
        'AES-256-GCM authentication tag verification failed — '
        'data may have been tampered with.',
      );
    } on VaultKeyException {
      rethrow;
    } catch (e) {
      throw VaultDecryptionException(
        'AES-256-GCM decryption failed',
        cause: e,
      );
    }
  }
}
