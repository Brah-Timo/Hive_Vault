// test/encryption/aes_gcm_test.dart

import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

Uint8List _randomKey() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

void main() {
  group('AesGcmEncryptionProvider', () {
    late AesGcmEncryptionProvider provider;

    setUp(() {
      provider = AesGcmEncryptionProvider(
        masterKey: _randomKey(),
        pbkdf2Iterations: 1000, // Low iterations for test speed
      );
    });

    // ── Integrity ─────────────────────────────────────────────────────────────
    group('Integrity', () {
      test('encrypt → decrypt restores original bytes', () async {
        final plain = utf8.encode('Sensitive data: salary=85000 DZD');
        final ciphertext = await provider.encrypt(Uint8List.fromList(plain));
        final decrypted = await provider.decrypt(ciphertext);
        expect(decrypted, equals(plain));
      });

      test('round-trip: empty bytes', () async {
        final plain = Uint8List(0);
        final cipher = await provider.encrypt(plain);
        final restored = await provider.decrypt(cipher);
        expect(restored, equals(plain));
      });

      test('round-trip: large blob (128 KB)', () async {
        final large = Uint8List.fromList(
          List.generate(131072, (i) => i % 256),
        );
        final cipher = await provider.encrypt(large);
        final restored = await provider.decrypt(cipher);
        expect(restored, equals(large));
      });

      test('round-trip: Arabic text', () async {
        final text = utf8.encode(
            'رقم الحساب البنكي: CPA 123456789 — رمز NIF: 987654321');
        final cipher = await provider.encrypt(Uint8List.fromList(text));
        final decrypted = await provider.decrypt(cipher);
        expect(decrypted, equals(text));
      });
    });

    // ── Security ──────────────────────────────────────────────────────────────
    group('Security', () {
      test('same plaintext produces different ciphertext each time (nonce randomness)', () async {
        final plain = utf8.encode('password: super_secret');
        final c1 = await provider.encrypt(Uint8List.fromList(plain));
        final c2 = await provider.encrypt(Uint8List.fromList(plain));
        expect(c1, isNot(equals(c2)),
            reason: 'Each encryption must use a fresh nonce and salt');
      });

      test('ciphertext does not contain plaintext', () async {
        final plain = utf8.encode('BANK_ACCOUNT_NUMBER_123456789');
        final cipher = await provider.encrypt(Uint8List.fromList(plain));
        // The ciphertext must not contain the original ASCII string
        final cipherStr = String.fromCharCodes(cipher);
        expect(cipherStr.contains('BANK_ACCOUNT_NUMBER'), isFalse);
      });

      test('tampered ciphertext raises IntegrityCheckException', () async {
        final plain = utf8.encode('test data for integrity check');
        final cipher = await provider.encrypt(Uint8List.fromList(plain));
        // Flip a byte in the ciphertext section (after 28-byte header)
        cipher[30] ^= 0xFF;
        expect(
          () => provider.decrypt(cipher),
          throwsA(isA<IntegrityCheckException>()),
        );
      });

      test('wrong key cannot decrypt', () async {
        final plain = utf8.encode('confidential payroll data');
        final cipher = await provider.encrypt(Uint8List.fromList(plain));

        final wrongKeyProvider = AesGcmEncryptionProvider(
          masterKey: _randomKey(), // different key
          pbkdf2Iterations: 1000,
        );
        expect(
          () => wrongKeyProvider.decrypt(cipher),
          throwsA(isA<HiveVaultException>()),
        );
      });
    });

    // ── Metadata ──────────────────────────────────────────────────────────────
    test('algorithmName is "AES-256-GCM"', () {
      expect(provider.algorithmName, equals('AES-256-GCM'));
    });

    test('supportsIntegrityCheck is true', () {
      expect(provider.supportsIntegrityCheck, isTrue);
    });

    test('headerFlag matches kEncryptionAesGcm', () {
      expect(provider.headerFlag, equals(kEncryptionAesGcm));
    });

    // ── Input Validation ──────────────────────────────────────────────────────
    test('decrypt throws on truncated input', () async {
      final tooShort = Uint8List(5);
      expect(
        () => provider.decrypt(tooShort),
        throwsA(isA<InvalidPayloadException>()),
      );
    });
  });
}
