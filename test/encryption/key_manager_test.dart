// test/encryption/key_manager_test.dart

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

import 'key_manager_test.mocks.dart';

@GenerateMocks([FlutterSecureStorage])
void main() {
  group('KeyManager', () {
    late MockFlutterSecureStorage mockStorage;
    late KeyManager keyManager;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      keyManager = KeyManager(storage: mockStorage);
    });

    // ── Key Generation ────────────────────────────────────────────────────────
    group('generateMasterKey', () {
      test('generates a 32-byte key', () {
        final key = KeyManager.generateMasterKey();
        expect(key.length, equals(32));
      });

      test('generates different keys each time', () {
        final k1 = KeyManager.generateMasterKey();
        final k2 = KeyManager.generateMasterKey();
        expect(k1, isNot(equals(k2)));
      });

      test('key contains non-zero bytes (not all zeros)', () {
        final key = KeyManager.generateMasterKey();
        expect(key.any((b) => b != 0), isTrue);
      });
    });

    // ── Store / Retrieve ──────────────────────────────────────────────────────
    group('storeKey / retrieveKey', () {
      test('stored key is retrievable', () async {
        final key = KeyManager.generateMasterKey();
        final encoded = key.map((b) => b.toString()).join(',');

        when(mockStorage.write(key: kMasterKeyStorageId, value: encoded))
            .thenAnswer((_) async {});
        when(mockStorage.read(key: kMasterKeyStorageId))
            .thenAnswer((_) async => encoded);

        await keyManager.storeKey(key);
        final retrieved = await keyManager.retrieveKey();
        expect(retrieved, equals(key));
      });

      test('retrieveKey returns null when no key stored', () async {
        when(mockStorage.read(key: kMasterKeyStorageId))
            .thenAnswer((_) async => null);
        final result = await keyManager.retrieveKey();
        expect(result, isNull);
      });
    });

    // ── getOrCreateMasterKey ──────────────────────────────────────────────────
    group('getOrCreateMasterKey', () {
      test('creates new key when none exists', () async {
        when(mockStorage.read(key: kMasterKeyStorageId))
            .thenAnswer((_) async => null);
        when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
            .thenAnswer((_) async {});

        final key = await keyManager.getOrCreateMasterKey();
        expect(key.length, equals(32));
        verify(mockStorage.write(
                key: kMasterKeyStorageId, value: anyNamed('value')))
            .called(1);
      });

      test('returns existing key without creating a new one', () async {
        final existing = KeyManager.generateMasterKey();
        final encoded = existing.map((b) => b.toString()).join(',');

        when(mockStorage.read(key: kMasterKeyStorageId))
            .thenAnswer((_) async => encoded);

        final key = await keyManager.getOrCreateMasterKey();
        expect(key, equals(existing));
        verifyNever(mockStorage.write(
            key: kMasterKeyStorageId, value: anyNamed('value')));
      });
    });

    // ── Key Rotation ──────────────────────────────────────────────────────────
    group('isRotationDue', () {
      test('returns true when no timestamp stored', () async {
        when(mockStorage.read(key: kKeyRotationTimestampId))
            .thenAnswer((_) async => null);
        expect(await keyManager.isRotationDue(90), isTrue);
      });

      test('returns false when key was rotated recently', () async {
        final recentTs = DateTime.now().toUtc().toIso8601String();
        when(mockStorage.read(key: kKeyRotationTimestampId))
            .thenAnswer((_) async => recentTs);
        expect(await keyManager.isRotationDue(90), isFalse);
      });

      test('returns true when rotation is overdue', () async {
        final oldTs = DateTime.now()
            .subtract(const Duration(days: 100))
            .toUtc()
            .toIso8601String();
        when(mockStorage.read(key: kKeyRotationTimestampId))
            .thenAnswer((_) async => oldTs);
        expect(await keyManager.isRotationDue(90), isTrue);
      });
    });
  });
}
