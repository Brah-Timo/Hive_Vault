# Core Layer — Interfaces, Config, Constants, Exceptions & Stats

> **Files**: `lib/src/core/`
>
> - `vault_interface.dart` — Public contract (`SecureStorageInterface`)
> - `vault_config.dart` — Master configuration + presets
> - `constants.dart` — All global constants and flag classes
> - `vault_exceptions.dart` — Exception hierarchy
> - `vault_stats.dart` — Immutable stats value objects
> - `sensitivity_level.dart` — Data-sensitivity enum
> - `encryption_config.dart` — Encryption settings
> - `compression_config.dart` — Compression settings
> - `indexing_config.dart` — Index settings

---

## 1. `vault_interface.dart` — `SecureStorageInterface`

The **sole public API** of HiveVault. All higher-level wrappers (`ReactiveVault`, shards, multi-box) implement this interface.

```dart
abstract class SecureStorageInterface {
  // ── Lifecycle ──────────────────────────────────────────────
  Future<void> initialize();
  Future<void> close();

  // ── Single-key CRUD ────────────────────────────────────────
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  });

  Future<T?> secureGet<T>(String key);
  Future<void> secureDelete(String key);
  Future<bool> secureContains(String key);
  Future<List<String>> getAllKeys();

  // ── Batch operations ───────────────────────────────────────
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  });
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys);
  Future<void> secureDeleteBatch(List<String> keys);

  // ── Search ─────────────────────────────────────────────────
  Future<List<T>> secureSearch<T>(String query);      // AND: all tokens
  Future<List<T>> secureSearchAny<T>(String query);   // OR:  any token
  Future<List<T>> secureSearchPrefix<T>(String prefix);
  Future<Set<String>> searchKeys(String query);        // returns keys only

  // ── Maintenance ────────────────────────────────────────────
  Future<void> rebuildIndex();
  Future<void> compact();
  void clearCache();

  // ── Import / Export ────────────────────────────────────────
  Future<Uint8List> exportEncrypted();
  Future<void> importEncrypted(Uint8List data);

  // ── Diagnostics ────────────────────────────────────────────
  Future<VaultStats> getStats();
  List<AuditEntry> getAuditLog({int limit = 50});
}
```

### Method Details

| Method | Description |
|---|---|
| `secureSave` | Serialize → compress → encrypt → wrap in envelope → persist. Optionally indexes `searchableText`. |
| `secureGet<T>` | Load payload → verify checksum → decrypt → decompress → deserialize to `T`. Returns `null` for missing keys. |
| `secureDelete` | Removes entry from box and index. |
| `secureContains` | Box membership check (no decryption). |
| `getAllKeys` | Returns all raw keys from the Hive box. |
| `secureSaveBatch` | Atomic parallel save of multiple entries. |
| `secureGetBatch` | Parallel load; missing keys are omitted from the result map. |
| `secureSearchAny` | Union of token matches (broader recall). |
| `secureSearch` | Intersection of all query tokens (higher precision). |
| `secureSearchPrefix` | Prefix scan on the inverted index. |
| `searchKeys` | Same as `secureSearch` but returns only the matching key strings. |
| `rebuildIndex` | Clears and re-builds the in-memory inverted index from existing box data. |
| `compact` | Triggers Hive compaction (rewrites the `.hive` file removing tombstones). |
| `exportEncrypted` | Exports all entries as a base64-JSON bundle, re-encrypted under the current key. |
| `importEncrypted` | Imports a bundle produced by `exportEncrypted`. |

---

## 2. `vault_config.dart` — `VaultConfig`

Master configuration aggregating compression, encryption, and indexing settings plus vault-level flags.

```dart
@immutable
class VaultConfig {
  const VaultConfig({
    this.compression = const CompressionConfig(),
    this.encryption = const EncryptionConfig(),
    this.indexing = const IndexingConfig(),
    this.enableAuditLog = true,
    this.enableIntegrityChecks = true,
    this.enableBackgroundProcessing = true,
    this.backgroundProcessingThreshold = kDefaultIsolateThreshold, // 64 KB
    this.memoryCacheSize = kDefaultCacheSize,                       // 100
    this.enableMemoryCache = true,
  });
}
```

### Field Reference

| Field | Default | Description |
|---|---|---|
| `compression` | `CompressionConfig()` | Compression algorithm and threshold |
| `encryption` | `EncryptionConfig()` | Encryption algorithm and key settings |
| `indexing` | `IndexingConfig()` | Full-text index configuration |
| `enableAuditLog` | `true` | Records every CRUD operation |
| `enableIntegrityChecks` | `true` | Appends/verifies SHA-256 checksum |
| `enableBackgroundProcessing` | `true` | Offloads large payloads to isolate |
| `backgroundProcessingThreshold` | 65536 | Byte threshold for isolate offload |
| `memoryCacheSize` | 100 | LRU cache entry count |
| `enableMemoryCache` | `true` | Enable in-memory read cache |

### Factory Presets

```dart
VaultConfig.erp()            // GZip-6, AES-256-GCM, full index, cache=200
VaultConfig.light()          // Lz4, AES-256-CBC, no index, no audit, cache=30
VaultConfig.debug()          // No compression, no encryption, full index, cache=50
VaultConfig.maxSecurity()    // GZip-9, AES-256-GCM 200k PBKDF2, key rotation
VaultConfig.maxPerformance() // Lz4, no encryption, full index, cache=500
```

### `copyWith`

```dart
final fastConfig = VaultConfig.erp().copyWith(
  memoryCacheSize: 500,
  enableAuditLog: false,
);
```

---

## 3. `constants.dart` — Global Constants

All magic numbers and flag values used across the library.

### Payload Format

```dart
const int kPayloadVersion = 1;     // Binary format version
const int kHeaderSize = 7;         // Header bytes: version(1)+comp(1)+enc(1)+len(4)
const int kDefaultMinCompressionSize = 64; // Min bytes to attempt compression
```

### Algorithm Parameters

```dart
const int kGcmNonceSize = 12;           // AES-GCM nonce (bytes)
const int kCbcIvSize = 16;              // AES-CBC IV (bytes)
const int kSaltSize = 16;               // PBKDF2 salt (bytes)
const int kAesKeySize = 32;             // AES-256 key = 32 bytes
const int kGcmTagSize = 16;             // GCM authentication tag (bytes)
const int kDefaultPbkdf2Iterations = 100000;  // PBKDF2 rounds
```

### Infrastructure

```dart
const int kDefaultIsolateThreshold = 65536;  // 64 KB isolate offload threshold
const int kDefaultCacheSize = 100;           // Default LRU cache capacity
const String kMasterKeyStorageId = 'hive_vault_master_key_v1';
```

### Flag Classes

```dart
class CompressionFlag {
  static const int none    = 0;
  static const int gzip    = 1;
  static const int lz4     = 2;
  static const int deflate = 3;
}

class EncryptionFlag {
  static const int none   = 0;
  static const int aesCbc = 1;
  static const int aesGcm = 2;
}
```

### GZip / Lz4 Magic Bytes

```dart
const int kGZipByte0 = 0x1f;  // GZip magic byte 0
const int kGZipByte1 = 0x8b;  // GZip magic byte 1
// Lz4 frame magic: 0x04, 0x22, 0x4d, 0x18
```

---

## 4. `vault_exceptions.dart` — Exception Hierarchy

```
VaultException (abstract)
├── VaultEncryptionException     — encryption failed
├── VaultDecryptionException     — decryption failed / wrong key
├── VaultIntegrityException      — SHA-256 checksum mismatch
├── VaultKeyException            — key derivation / storage error
├── VaultCompressionException    — compression failed
├── VaultDecompressionException  — decompression failed / corrupt data
├── VaultInitException           — vault initialization error
├── VaultStorageException        — Hive read/write error
├── VaultPayloadException        — malformed binary payload
├── VaultConfigException         — invalid configuration
├── VaultExportException         — export operation failed
└── VaultImportException         — import operation failed
```

All exceptions carry:
- `String message` — human-readable description
- `Object? cause` — the underlying exception (optional)

```dart
@override
String toString() => 'VaultEncryptionException: $message'
    '${cause != null ? '\nCaused by: $cause' : ''}';
```

### Usage Example

```dart
try {
  await vault.secureGet<Map>('CLIENT-001');
} on VaultDecryptionException catch (e) {
  // Wrong master key or corrupt ciphertext
  print('Decryption failed: ${e.message}');
} on VaultIntegrityException catch (e) {
  // Data was tampered with
  print('Integrity check failed: ${e.message}');
} on VaultException catch (e) {
  // Any other vault error
  print('Vault error: $e');
}
```

---

## 5. `vault_stats.dart` — Statistics Value Objects

### `IndexStats`

```dart
@immutable
class IndexStats {
  final int totalEntries;              // Number of indexed keys
  final int totalKeywords;             // Unique tokens in the index
  final double averageKeywordsPerEntry;
  final int memoryEstimateBytes;

  String get memoryLabel;              // e.g., "2.4 MB"

  const IndexStats.empty();           // Zero-value constructor
}
```

### `VaultStats`

```dart
@immutable
class VaultStats {
  final String boxName;
  final int totalEntries;
  final int cacheSize;
  final int cacheCapacity;
  final double cacheHitRatio;           // 0.0..1.0
  final String compressionAlgorithm;   // e.g., "GZip"
  final String encryptionAlgorithm;    // e.g., "AES-256-GCM"
  final IndexStats indexStats;
  final int totalBytesSaved;           // Bytes saved by compression
  final int totalBytesWritten;
  final int totalWrites;
  final int totalReads;
  final int totalSearches;
  final DateTime openedAt;

  // Derived
  double get compressionRatio;         // 0.0..1.0
  String get compressionRatioLabel;    // e.g., "42.3%"
  Duration get uptime;
}
```

### Printing Stats

```dart
final stats = await vault.getStats();
print(stats);
// Output:
// ══════════════════════════════════════
//   HiveVault Stats — products
// ══════════════════════════════════════
//   Entries        : 1,247
//   Cache          : 87 / 200 (43.5%)
//   Cache hits     : 94.2%
//   Compression    : GZip (ratio: 61.3%)
//   Encryption     : AES-256-GCM
//   Index          : 1,247 entries, 18,432 keywords (2.1 MB)
//   Writes / Reads : 3,481 / 12,063
//   Uptime         : 2h 14m
```

---

## 6. `sensitivity_level.dart` — `SensitivityLevel`

Controls per-entry encryption behaviour when selective encryption is enabled.

```dart
enum SensitivityLevel {
  /// No encryption — data stored as compressed plaintext.
  none,

  /// Standard encryption (AES-256-CBC by default).
  standard,

  /// High security encryption (AES-256-GCM with PBKDF2 derivation).
  high,

  /// Selective — uses the vault's defaultSensitivity unless overridden per-key.
  selective,
}
```

```dart
// Save payslip with maximum protection regardless of vault default
await vault.secureSave(
  'PAY-2024-001',
  payslipData,
  sensitivity: SensitivityLevel.high,
);
```

---

## 7. `encryption_config.dart` — `EncryptionConfig`

```dart
class EncryptionConfig {
  const EncryptionConfig({
    this.defaultSensitivity = SensitivityLevel.high,
    this.pbkdf2Iterations = kDefaultPbkdf2Iterations,     // 100,000
    this.enableSelectiveEncryption = false,
    this.sensitiveKeys = const {},
    this.enableIntegrityCheck = true,
    this.enableKeyRotation = false,
    this.keyRotationDays = 90,
  });
}
```

| Field | Description |
|---|---|
| `defaultSensitivity` | Default encryption level for all entries |
| `pbkdf2Iterations` | PBKDF2 rounds (higher = slower but stronger) |
| `enableSelectiveEncryption` | Allow per-entry sensitivity override |
| `sensitiveKeys` | Keys that always get `SensitivityLevel.high` |
| `enableIntegrityCheck` | Verify GCM authentication tag on decrypt |
| `enableKeyRotation` | Enables `KeyRotationScheduler` |
| `keyRotationDays` | Days before triggering automatic rotation |

---

## 8. `compression_config.dart` — `CompressionConfig`

```dart
class CompressionConfig {
  const CompressionConfig({
    this.strategy = CompressionStrategy.gzip,
    this.minimumSizeForCompression = 64,
    this.gzipLevel = 6,
    this.useIsolateForLargeData = true,
    this.isolateThreshold = 65536,   // 64 KB
  });
}

enum CompressionStrategy { none, gzip, lz4, deflate, auto }
```

| Strategy | Best for | Speed | Ratio |
|---|---|---|---|
| `none` | Binary/images | — | — |
| `gzip` | Text, JSON | Medium | High |
| `lz4` | Any, speed priority | Fast | Medium |
| `deflate` | Interoperability | Medium | High |
| `auto` | Mixed workloads | Adaptive | Adaptive |

---

## 9. `indexing_config.dart` — `IndexingConfig`

```dart
class IndexingConfig {
  const IndexingConfig({
    this.enableIndexing = true,
    this.minimumTokenLength = 2,
    this.maxTokensPerEntry = 100,
    this.indexableFields = const {},
    this.stopWords = const {'the', 'a', 'an', 'in', 'on', 'at', 'to'},
    this.caseSensitive = false,
    this.enableArabicNormalization = true,
  });
}
```

| Field | Description |
|---|---|
| `enableIndexing` | Turn full-text search on/off |
| `minimumTokenLength` | Tokens shorter than this are ignored |
| `maxTokensPerEntry` | Cap on tokens extracted per entry |
| `indexableFields` | When non-empty, only index these JSON fields |
| `stopWords` | Words excluded from the index |
| `caseSensitive` | Normally `false` for better recall |
| `enableArabicNormalization` | Strips harakat diacritics for Arabic text |
