# Binary Layer

> **Files**: `lib/src/binary/`
>
> - `binary_processor.dart` — Serialization, payload framing, SHA-256 integrity
> - `payload_info.dart` — Immutable parsed payload header model

---

## 1. `binary_processor.dart` — `BinaryProcessor`

Handles all byte-level operations: serialization, framing, checksumming, and deserialization.

```dart
class BinaryProcessor {
  final bool enableIntegrityChecks;

  const BinaryProcessor({this.enableIntegrityChecks = true});
}
```

---

### Payload Layout

```
Byte   Size    Field
─────  ──────  ──────────────────────────────────────────────────
0      1 byte  Format version (uint8) — currently 0x01
1      1 byte  Compression flag (uint8) — see CompressionFlag
2      1 byte  Encryption flag (uint8) — see EncryptionFlag
3-6    4 bytes Data length (uint32 big-endian)
7..N   N bytes Compressed + encrypted payload data
N+1..  32 bytes SHA-256 checksum [only when enableIntegrityChecks = true]
```

Total overhead:
- **7 bytes** minimum (header only, no integrity)
- **39 bytes** with integrity check (7 header + 32 SHA-256)

---

### Serialization — `objectToBytes`

```dart
static Uint8List objectToBytes(dynamic object)
```

Converts any JSON-serializable Dart object to `Uint8List`:

| Type | Conversion |
|---|---|
| `Uint8List` | Returned as-is |
| `List<int>` | `Uint8List.fromList(...)` |
| `String` | UTF-8 encoded |
| `Map<String, dynamic>` | `jsonEncode` → UTF-8 |
| `List<dynamic>` | `jsonEncode` → UTF-8 |
| `num` / `bool` | `.toString()` → UTF-8 |
| Other | Throws `VaultPayloadException` |

### Deserialization — `bytesToObject<T>`

```dart
static T bytesToObject<T>(Uint8List bytes)
```

Converts `Uint8List` back to type `T`:

| Type T | Conversion |
|---|---|
| `Uint8List` | Returned as-is |
| `String` | UTF-8 decoded |
| `Map` | UTF-8 decode → `jsonDecode` |
| `List` | UTF-8 decode → `jsonDecode` |
| `dynamic` / `Object` | UTF-8 decode → `jsonDecode` (or raw string if JSON fails) |

---

### Creating a Payload — `createPayload`

```dart
Future<Uint8List> createPayload({
  required Uint8List data,
  required int compressionFlag,
  required int encryptionFlag,
}) async
```

Steps:
1. Compute SHA-256 of `data` (if `enableIntegrityChecks`)
2. Allocate output buffer: `kHeaderSize + data.length + (checksum?.length ?? 0)`
3. Write header fields at offsets 0..6
4. Copy `data` bytes starting at offset 7
5. Append SHA-256 checksum (32 bytes) if enabled

```dart
// Example: create a payload for compressed+encrypted data
final payload = await processor.createPayload(
  data: encryptedBytes,
  compressionFlag: CompressionFlag.gzip,
  encryptionFlag: EncryptionFlag.aesGcm,
);
```

---

### Parsing a Payload — `parsePayload`

```dart
Future<PayloadInfo> parsePayload(Uint8List payload) async
```

Steps:
1. Check `payload.length >= kHeaderSize` (7 bytes minimum)
2. Read header fields: version, compressionFlag, encryptionFlag, dataLength
3. Validate version == `kPayloadVersion` (1)
4. Extract data bytes: `payload[7 .. 7+dataLength]`
5. If `enableIntegrityChecks`:
   - Extract stored checksum: `payload[7+dataLength ..]`
   - Compute `sha256(data)`
   - Compare with constant-time equality → throw `VaultIntegrityException` on mismatch
6. Return `PayloadInfo`

**Throws**:
- `VaultPayloadException` — too short, wrong version, length mismatch
- `VaultIntegrityException` — SHA-256 mismatch

---

### Checksum Utilities

```dart
// Compute SHA-256 of data
static Future<Uint8List> computeChecksum(Uint8List data)
```

Uses the `cryptography` package's `Sha256()` algorithm.

#### Constant-Time Comparison

```dart
static bool _constantTimeEquals(Uint8List a, Uint8List b)
```

Prevents timing attacks by XORing all bytes and checking the accumulated difference:

```dart
int diff = 0;
for (int i = 0; i < a.length; i++) {
  diff |= a[i] ^ b[i];
}
return diff == 0;  // No short-circuit
```

---

### Full Save Pipeline (Context)

```dart
// In HiveVaultImpl.secureSave:

// 1. Serialize
final rawBytes = BinaryProcessor.objectToBytes(value);

// 2. Compress
final compressed = compressionProvider.compress(rawBytes);
final compressionFlag = compressionProvider.headerFlag;

// 3. Encrypt
final encrypted = await encryptionProvider.encrypt(compressed);
final encryptionFlag = encryptionProvider.headerFlag;

// 4. Frame + checksum
final payload = await binaryProcessor.createPayload(
  data: encrypted,
  compressionFlag: compressionFlag,
  encryptionFlag: encryptionFlag,
);

// 5. Store
await box.put(key, payload);
```

### Full Read Pipeline (Context)

```dart
// In HiveVaultImpl.secureGet:

// 1. Load
final rawPayload = box.get(key);
if (rawPayload == null) return null;

// 2. Parse + verify checksum
final info = await binaryProcessor.parsePayload(rawPayload);

// 3. Decrypt
final decrypted = await encryptionProvider.decrypt(info.data);

// 4. Decompress (using flag from info)
final Uint8List decompressed;
switch (info.compressionFlag) {
  case CompressionFlag.gzip:    decompressed = gzipProvider.decompress(decrypted);
  case CompressionFlag.lz4:     decompressed = lz4Provider.decompress(decrypted);
  case CompressionFlag.deflate: decompressed = deflateProvider.decompress(decrypted);
  default:                      decompressed = decrypted;
}

// 5. Deserialize
return BinaryProcessor.bytesToObject<T>(decompressed);
```

---

## 2. `payload_info.dart` — `PayloadInfo`

Immutable data class representing the parsed header of a HiveVault binary payload.

```dart
@immutable
class PayloadInfo {
  final int version;           // Format version (must be kPayloadVersion = 1)
  final int compressionFlag;   // 0=none, 1=gzip, 2=lz4, 3=deflate
  final int encryptionFlag;    // 0=none, 1=AES-CBC, 2=AES-GCM
  final Uint8List data;        // Raw payload data (after the header)
}
```

### Derived Properties

```dart
bool get isCompressed => compressionFlag != CompressionFlag.none;
bool get isEncrypted  => encryptionFlag  != EncryptionFlag.none;

String get compressionLabel {
  // Returns: 'GZip', 'Lz4', 'Deflate', or 'None'
}

String get encryptionLabel {
  // Returns: 'AES-256-GCM', 'AES-256-CBC', or 'None'
}
```

### `toString` Example

```
PayloadInfo(v1, compression: GZip, encryption: AES-256-GCM, dataLen: 412)
```

---

## Integrity Check Behaviour

| `enableIntegrityChecks` | On write | On read |
|---|---|---|
| `true` (default) | Appends SHA-256 of encrypted data | Verifies SHA-256 before returning |
| `false` | No checksum appended | No checksum verification |

When integrity checks are enabled:
- Detect storage corruption (bit rot, disk errors)
- Detect tampered payloads (someone modified the `.hive` file directly)
- Small overhead: ~32 bytes per entry + SHA-256 compute time
