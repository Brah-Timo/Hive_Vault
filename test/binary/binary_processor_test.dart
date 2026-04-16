// test/binary/binary_processor_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for BinaryProcessor: serialisation, framing, and checksums.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:hive_vault/hive_vault.dart';

void main() {
  group('BinaryProcessor — objectToBytes', () {
    test('converts String to UTF-8 bytes', () {
      final bytes = BinaryProcessor.objectToBytes('Hello');
      expect(utf8.decode(bytes), equals('Hello'));
    });

    test('converts Map to JSON UTF-8 bytes', () {
      final map = {'name': 'Ahmed', 'amount': 1000};
      final bytes = BinaryProcessor.objectToBytes(map);
      final decoded = jsonDecode(utf8.decode(bytes));
      expect(decoded['name'], equals('Ahmed'));
      expect(decoded['amount'], equals(1000));
    });

    test('converts List to JSON UTF-8 bytes', () {
      final list = [1, 2, 3, 'four'];
      final bytes = BinaryProcessor.objectToBytes(list);
      final decoded = jsonDecode(utf8.decode(bytes));
      expect(decoded, equals(list));
    });

    test('passes Uint8List through unchanged', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(BinaryProcessor.objectToBytes(original), equals(original));
    });

    test('converts bool to string bytes', () {
      final bytes = BinaryProcessor.objectToBytes(true);
      expect(utf8.decode(bytes), equals('true'));
    });

    test('converts int to string bytes', () {
      final bytes = BinaryProcessor.objectToBytes(42);
      expect(utf8.decode(bytes), equals('42'));
    });

    test('throws VaultPayloadException for unsupported type', () {
      expect(
        () => BinaryProcessor.objectToBytes(DateTime.now()),
        throwsA(isA<VaultPayloadException>()),
      );
    });
  });

  group('BinaryProcessor — bytesToObject', () {
    test('deserialises to String', () {
      final bytes = Uint8List.fromList(utf8.encode('Hello World'));
      expect(BinaryProcessor.bytesToObject<String>(bytes), equals('Hello World'));
    });

    test('deserialises to Map', () {
      final json = jsonEncode({'key': 'value'});
      final bytes = Uint8List.fromList(utf8.encode(json));
      final result = BinaryProcessor.bytesToObject<Map>(bytes);
      expect(result['key'], equals('value'));
    });

    test('returns Uint8List unchanged when T is Uint8List', () {
      final bytes = Uint8List.fromList([9, 8, 7]);
      expect(BinaryProcessor.bytesToObject<Uint8List>(bytes), equals(bytes));
    });
  });

  group('BinaryProcessor — createPayload / parsePayload', () {
    late BinaryProcessor processor;

    setUp(() => processor = const BinaryProcessor(enableIntegrityChecks: false));

    test('creates payload with correct header values', () async {
      final data = Uint8List.fromList([10, 20, 30]);
      final payload = await processor.createPayload(
        data: data,
        compressionFlag: CompressionFlag.gzip,
        encryptionFlag: EncryptionFlag.aesGcm,
      );
      expect(payload.length, greaterThanOrEqualTo(kHeaderSize + data.length));
    });

    test('parse round-trip returns correct PayloadInfo', () async {
      final data = Uint8List.fromList(utf8.encode('Test payload'));
      final payload = await processor.createPayload(
        data: data,
        compressionFlag: CompressionFlag.lz4,
        encryptionFlag: EncryptionFlag.aesCbc,
      );
      final info = await processor.parsePayload(payload);
      expect(info.version, equals(kPayloadVersion));
      expect(info.compressionFlag, equals(CompressionFlag.lz4));
      expect(info.encryptionFlag, equals(EncryptionFlag.aesCbc));
      expect(info.data, equals(data));
    });

    test('parse throws VaultPayloadException for short payload', () async {
      final tiny = Uint8List(3);
      expect(
        () async => processor.parsePayload(tiny),
        throwsA(isA<VaultPayloadException>()),
      );
    });
  });

  group('BinaryProcessor — integrity checks', () {
    late BinaryProcessor processor;

    setUp(() => processor = const BinaryProcessor(enableIntegrityChecks: true));

    test('creates and verifies checksum successfully', () async {
      final data = Uint8List.fromList(utf8.encode('Integrity test data'));
      final payload = await processor.createPayload(
        data: data,
        compressionFlag: CompressionFlag.none,
        encryptionFlag: EncryptionFlag.none,
      );
      // Should parse without throwing.
      final info = await processor.parsePayload(payload);
      expect(info.data, equals(data));
    });

    test('throws VaultIntegrityException when payload is tampered', () async {
      final data = Uint8List.fromList(utf8.encode('tamper test'));
      final payload = await processor.createPayload(
        data: data,
        compressionFlag: CompressionFlag.none,
        encryptionFlag: EncryptionFlag.none,
      );
      // Tamper with a byte in the middle of the data section.
      final tampered = Uint8List.fromList(payload);
      tampered[kHeaderSize] ^= 0xFF; // flip bits

      expect(
        () async => processor.parsePayload(tampered),
        throwsA(isA<VaultIntegrityException>()),
      );
    });
  });

  group('BinaryProcessor — computeChecksum', () {
    test('produces consistent 32-byte SHA-256 hash', () async {
      final data = Uint8List.fromList(utf8.encode('consistent'));
      final hash1 = await BinaryProcessor.computeChecksum(data);
      final hash2 = await BinaryProcessor.computeChecksum(data);
      expect(hash1.length, equals(32));
      expect(hash1, equals(hash2));
    });

    test('different data produces different hash', () async {
      final h1 = await BinaryProcessor.computeChecksum(_utf8('aaa'));
      final h2 = await BinaryProcessor.computeChecksum(_utf8('bbb'));
      expect(h1, isNot(equals(h2)));
    });
  });
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
