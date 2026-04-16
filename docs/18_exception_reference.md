# Exception Reference

> **File**: `lib/src/core/vault_exceptions.dart`

Complete reference for every exception type in HiveVault.

---

## Exception Hierarchy

```
VaultException (abstract base)
├── VaultEncryptionException
├── VaultDecryptionException
├── VaultIntegrityException
├── VaultKeyException
├── VaultCompressionException
├── VaultDecompressionException
├── VaultInitException
├── VaultStorageException
├── VaultPayloadException
├── VaultConfigException
├── VaultExportException
├── VaultImportException
└── VaultTransactionException     (in transaction/vault_transaction.dart)

RateLimitExceededException        (in cache/rate_limiter.dart, extends VaultException)
CompressionException              (alias for VaultCompressionException)
```

---

## Base Class

```dart
abstract class VaultException implements Exception {
  const VaultException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '${runtimeType}: $message'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}
```

---

## Exception Details

### `VaultEncryptionException`

**When**: AES encryption fails (invalid key length, provider error).

```dart
throw VaultEncryptionException('AES-256-GCM encryption failed', cause: e);
```

**Recovery**: Check that the master key is 32 bytes. Verify the `encrypt` package is installed.

---

### `VaultDecryptionException`

**When**: Decryption fails — wrong key, corrupt ciphertext, or truncated data.

```dart
throw VaultDecryptionException(
  'AES-256-CBC decryption failed — wrong key or corrupt data',
  cause: e,
);
```

**Recovery**: This is the most common vault error. Common causes:
1. Using a different master key than was used to encrypt
2. The `.hive` file was manually modified
3. Data was partially written (crash during write)

---

### `VaultIntegrityException`

**When**: SHA-256 checksum does not match the stored checksum.

```dart
throw VaultIntegrityException(
  'Payload checksum mismatch — data may be corrupt or tampered.',
);
```

**Recovery**: The stored data is corrupt or has been tampered with. Options:
- Delete the entry and re-save from a source of truth
- Restore from backup

---

### `VaultKeyException`

**When**: Key derivation fails, secure storage is unavailable, or key operations fail.

```dart
throw VaultKeyException('PBKDF2 key derivation failed', cause: e);
```

**Recovery**: Check that `flutter_secure_storage` is configured correctly in your app (keychain entitlements on iOS, encrypted shared prefs on Android).

---

### `VaultCompressionException`

**When**: Compression fails (invalid data, provider error).

```dart
throw VaultCompressionException('GZip compression failed', cause: e);
```

**Recovery**: Rare in practice. Try `CompressionStrategy.lz4` or `CompressionStrategy.none`.

---

### `VaultDecompressionException`

**When**: Decompression fails — corrupt compressed data, wrong algorithm, magic mismatch.

```dart
throw VaultDecompressionException(
  'Lz4 decompression: output size mismatch (expected 1024, got 980)',
);
```

**Recovery**: The stored compressed data is corrupt. Delete and re-save.

---

### `VaultInitException`

**When**: Vault initialization fails — Hive cannot open the box, permission error, storage full.

```dart
throw VaultInitException('Failed to open Hive box "invoices"', cause: e);
```

**Recovery**: Check storage permissions. Ensure `HiveVault.initHive()` was called first. Check available storage space.

---

### `VaultStorageException`

**When**: Hive read/write operation fails after initialization. Can also occur during migration.

```dart
throw VaultStorageException('Migration failed for key "PROD-001"', cause: e);
```

**Recovery**: Could be a transient I/O error. Retry the operation. If persistent, the `.hive` file may be corrupt.

---

### `VaultPayloadException`

**When**: The binary payload cannot be parsed — too short, wrong version, length mismatch.

```dart
throw VaultPayloadException(
  'Payload too short: 4 bytes (minimum 7)',
);
throw VaultPayloadException(
  'Unsupported payload version: 2 (current: 1)',
);
```

**Recovery**: The entry was written by a different version of HiveVault. Run `MigrationManager` if upgrading from an older version.

---

### `VaultConfigException`

**When**: An invalid configuration is provided.

```dart
throw VaultConfigException(
  'AES-CBC key must be exactly 32 bytes (got 16)',
);
throw VaultConfigException(
  'Unknown CompressionStrategy: invalid',
);
```

**Recovery**: Fix the configuration. Check `VaultConfig`, `EncryptionConfig`, `CompressionConfig` field values.

---

### `VaultExportException`

**When**: `exportEncrypted()` fails (I/O error, serialization failure).

```dart
throw VaultExportException('Export failed after 842 entries', cause: e);
```

---

### `VaultImportException`

**When**: `importEncrypted()` fails (invalid JSON, base64 decode error, Hive write error).

```dart
throw VaultImportException('Import failed: invalid base64 for key "INV-001"', cause: e);
```

---

### `VaultTransactionException`

**When**: Transaction operation on wrong state (e.g., writing to a committed transaction).

```dart
throw VaultTransactionException(
  'Cannot write to a committed transaction',
);
```

---

### `RateLimitExceededException`

**When**: A `VaultRateLimiter`, `TokenBucket`, `SlidingWindowLimiter`, or `FixedWindowLimiter` exhausts its limit.

```dart
throw RateLimitExceededException(
  'Write rate limit exceeded',
);
```

---

## Catching Exceptions

### Catch specific types

```dart
try {
  await vault.secureGet<Map>('INV-001');
} on VaultDecryptionException {
  // Wrong key or corrupt data
} on VaultIntegrityException {
  // Tampered or corrupt data
} on VaultException catch (e) {
  // Any other vault error
  print(e.message);
  if (e.cause != null) print('Caused by: ${e.cause}');
}
```

### Catch all vault errors

```dart
try {
  await vault.secureSave('KEY', value);
} on VaultException catch (e) {
  _handleVaultError(e);
} catch (e) {
  // Non-vault exception (shouldn't happen in normal use)
}
```

### Check audit log for errors

```dart
final errors = vault.getAuditLog(limit: 200)
    .where((e) => e.action == AuditAction.error)
    .toList();
for (final err in errors) {
  print('${err.timestamp}: ${err.key} — ${err.details}');
}
```
