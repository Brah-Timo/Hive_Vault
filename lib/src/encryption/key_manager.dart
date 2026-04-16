// lib/src/encryption/key_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Secure key generation, derivation, storage, and rotation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';
import '../core/vault_exceptions.dart';

/// Manages cryptographic keys for HiveVault.
///
/// Responsibilities:
/// - Generating cryptographically secure random keys.
/// - Deriving keys from user-supplied passwords via PBKDF2-HMAC-SHA256.
/// - Persisting master keys in [FlutterSecureStorage] (OS Keychain / Keystore).
/// - Supporting key rotation without data loss.
class KeyManager {
  KeyManager._();

  // ─── Key generation ───────────────────────────────────────────────────────

  /// Generates a cryptographically secure 256-bit (32-byte) random key.
  static Uint8List generateMasterKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(kAesKeySize, (_) => random.nextInt(256)),
    );
  }

  /// Generates a cryptographically secure random byte array of [length] bytes.
  static Uint8List generateRandom(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  // ─── Key derivation ───────────────────────────────────────────────────────

  /// Derives a 256-bit key from [password] using PBKDF2-HMAC-SHA256.
  ///
  /// Parameters:
  /// - [password]   The user-supplied passphrase (UTF-8 encoded internally).
  /// - [salt]       A 16-byte random salt. Generate with [generateRandom].
  /// - [iterations] Number of rounds (OWASP min: 600k for SHA-1; 100k+ for SHA-256).
  ///
  /// Returns a 32-byte derived key.
  static Future<Uint8List> deriveKeyFromPassword({
    required String password,
    required Uint8List salt,
    int iterations = kDefaultPbkdf2Iterations,
  }) async {
    try {
      final algorithm = crypto.Pbkdf2(
        macAlgorithm: crypto.Hmac.sha256(),
        iterations: iterations,
        bits: kAesKeySize * 8, // 256 bits
      );
      final passwordBytes = utf8.encode(password);
      final secretKey = await algorithm.deriveKeyFromPassword(
        password: utf8.decode(passwordBytes),
        nonce: salt,
      );
      final keyBytes = await secretKey.extractBytes();
      return Uint8List.fromList(keyBytes);
    } catch (e) {
      throw VaultKeyException('PBKDF2 key derivation failed', cause: e);
    }
  }

  // ─── Secure persistence ───────────────────────────────────────────────────

  static FlutterSecureStorage? _storage;

  static FlutterSecureStorage get _secureStorage {
    _storage ??= const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    return _storage!;
  }

  /// Persists [key] in the OS secure store under [keyId].
  ///
  /// On Android this uses EncryptedSharedPreferences backed by Android Keystore.
  /// On iOS this uses the Keychain.
  static Future<void> storeKey(String keyId, Uint8List key) async {
    try {
      final encoded = base64.encode(key);
      await _secureStorage.write(key: keyId, value: encoded);
    } catch (e) {
      throw VaultKeyException(
        'Failed to persist key "$keyId" in secure storage',
        cause: e,
      );
    }
  }

  /// Retrieves the key stored under [keyId].
  ///
  /// Returns `null` if no key has been stored for that ID.
  static Future<Uint8List?> retrieveKey(String keyId) async {
    try {
      final encoded = await _secureStorage.read(key: keyId);
      if (encoded == null || encoded.isEmpty) return null;
      return Uint8List.fromList(base64.decode(encoded));
    } catch (e) {
      throw VaultKeyException(
        'Failed to read key "$keyId" from secure storage',
        cause: e,
      );
    }
  }

  /// Deletes the key stored under [keyId] from secure storage.
  static Future<void> deleteKey(String keyId) async {
    try {
      await _secureStorage.delete(key: keyId);
    } catch (e) {
      throw VaultKeyException(
        'Failed to delete key "$keyId" from secure storage',
        cause: e,
      );
    }
  }

  /// Returns `true` if a key with [keyId] exists in secure storage.
  static Future<bool> keyExists(String keyId) async {
    try {
      final value = await _secureStorage.read(key: keyId);
      return value != null && value.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─── Get-or-create pattern ────────────────────────────────────────────────

  /// Returns the master key for [keyId], generating and persisting a new one
  /// if none exists yet.
  ///
  /// This is the recommended entry point for vault initialisation.
  static Future<Uint8List> getOrCreateMasterKey(String keyId) async {
    final existing = await retrieveKey(keyId);
    if (existing != null) return existing;

    final newKey = generateMasterKey();
    await storeKey(keyId, newKey);
    return newKey;
  }

  // ─── Key rotation ─────────────────────────────────────────────────────────

  /// Rotates the master key: generates a new key, persists it, and returns
  /// both the old and new keys so the caller can re-encrypt stored data.
  ///
  /// The caller MUST re-encrypt all vault entries before deleting the old key.
  static Future<KeyRotationResult> rotateKey(String keyId) async {
    final oldKey = await retrieveKey(keyId);
    if (oldKey == null) {
      throw VaultKeyException(
        'Cannot rotate key "$keyId" — no existing key found',
      );
    }

    final newKey = generateMasterKey();
    // Store new key under a temporary ID while rotation is in progress.
    final tempKeyId = '${keyId}_rotating';
    await storeKey(tempKeyId, newKey);

    return KeyRotationResult(
      oldKey: oldKey,
      newKey: newKey,
      oldKeyId: keyId,
      newKeyId: tempKeyId,
    );
  }

  /// Commits a key rotation: promotes the temporary key to the permanent ID
  /// and deletes the old key.
  static Future<void> commitRotation(KeyRotationResult rotation) async {
    await storeKey(rotation.oldKeyId, rotation.newKey);
    await deleteKey(rotation.newKeyId);
  }

  /// Aborts a key rotation: deletes the temporary new key.
  static Future<void> abortRotation(KeyRotationResult rotation) async {
    await deleteKey(rotation.newKeyId);
  }

  // ─── Metadata ─────────────────────────────────────────────────────────────

  /// Stores the creation timestamp for [keyId] so the vault can determine
  /// when key rotation is due.
  static Future<void> storeKeyCreationDate(String keyId) async {
    final dateKey = '${keyId}_created';
    final iso = DateTime.now().toIso8601String();
    try {
      await _secureStorage.write(key: dateKey, value: iso);
    } catch (_) {
      // Non-fatal — key rotation date tracking is best-effort.
    }
  }

  /// Returns the creation date for [keyId], or `null` if unknown.
  static Future<DateTime?> getKeyCreationDate(String keyId) async {
    try {
      final dateKey = '${keyId}_created';
      final iso = await _secureStorage.read(key: dateKey);
      if (iso == null) return null;
      return DateTime.tryParse(iso);
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` if the key for [keyId] is older than [maxAgeDays].
  static Future<bool> isKeyRotationDue(String keyId, int maxAgeDays) async {
    final created = await getKeyCreationDate(keyId);
    if (created == null) return false;
    final age = DateTime.now().difference(created).inDays;
    return age >= maxAgeDays;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Holds both old and new key material during a key rotation operation.
class KeyRotationResult {
  final Uint8List oldKey;
  final Uint8List newKey;
  final String oldKeyId;
  final String newKeyId;

  const KeyRotationResult({
    required this.oldKey,
    required this.newKey,
    required this.oldKeyId,
    required this.newKeyId,
  });
}
