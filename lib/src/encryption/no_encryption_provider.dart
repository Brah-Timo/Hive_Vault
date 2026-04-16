// lib/src/encryption/no_encryption_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Pass-through provider (no encryption).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import '../core/constants.dart';
import 'encryption_provider.dart';

/// A [EncryptionProvider] that applies no encryption.
///
/// ⚠️  For development, testing, and non-sensitive data only.
///     Do NOT use in production for sensitive data.
class NoEncryptionProvider extends EncryptionProvider {
  const NoEncryptionProvider();

  @override
  String get algorithmName => 'None';

  @override
  int get headerFlag => EncryptionFlag.none;

  @override
  bool get supportsIntegrityCheck => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<Uint8List> encrypt(Uint8List plainData) async => plainData;

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData) async => encryptedData;
}
