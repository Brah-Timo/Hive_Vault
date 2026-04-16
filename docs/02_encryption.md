# Encryption Layer

> **Files**: `lib/src/encryption/`
>
> - `encryption_provider.dart` — Abstract interface
> - `aes_gcm_provider.dart` — AES-256-GCM (authenticated)
> - `aes_cbc_provider.dart` — AES-256-CBC (legacy/compat)
> - `no_encryption_provider.dart` — Pass-through (no-op)
> - `encryption_config.dart` — Per-vault encryption settings
> - `encryption_factory.dart` — Factory: config + key → provider
> - `key_manager.dart` — Key generation, PBKDF2 derivation, secure storage
> - `key_rotation_scheduler.dart` — Automated key rotation with policies
> - `sensitivity_level.dart` — Data-sensitivity enum (re-export)

---

## 1. `encryption_provider.dart` — Abstract Interface

```dart
abstract class EncryptionProvider {
  /// Algorithm identifier for stats and audit logs.
  String get algorithmName;

  /// Integer flag written into the binary payload header.
  /// Must match one of the [EncryptionFlag] constants (0, 1, 2).
  int get headerFlag;

  /// Whether this provider can verify data integrity.
  /// true for AES-GCM (AEAD), false for AES-CBC and None.
  bool get supportsIntegrityCheck;

  Future<Uint8List> encrypt(Uint8List plainData);
  Future<Uint8List> decrypt(Uint8List encryptedData);
  Future<void> dispose();   // Release any held resources
}
```

---

## 2. `aes_gcm_provider.dart` — AES-256-GCM

The **recommended** encryption provider. Provides both confidentiality and authenticity.

### Security Properties

| Property | Detail |
|---|---|
| Algorithm | AES-256-GCM (AEAD) |
| Key derivation | PBKDF2-HMAC-SHA256, fresh 16-byte salt per call |
| Nonce | 12-byte cryptographically random per call |
| Authentication tag | 128-bit GCM tag (appended by `cryptography` package) |
| Integrity | Any bit flip in the ciphertext causes `VaultDecryptionException` |
| Same-plaintext output | Always different (different salt + nonce each time) |

### Envelope Layout

```
Offset  Size     Field
──────  ───────  ──────────────────────────────────────────────────
0       16 bytes Salt  (PBKDF2 input for per-call key derivation)
16      12 bytes Nonce (AES-GCM random nonce)
28      N bytes  Ciphertext + 16-byte GCM authentication tag
```

Total overhead per entry: **28 bytes** header + **16 bytes** GCM tag.

### Constructor

```dart
const AesGcmProvider({
  required Uint8List masterKey,         // 32-byte (256-bit) master key
  int pbkdf2Iterations = 100000,        // PBKDF2 rounds
});
```

### Encrypt Flow

```
1. Generate random salt(16) + nonce(12)
2. Derive 256-bit sub-key: PBKDF2(masterKey, salt, iterations)
3. AES-256-GCM encrypt(plainData, subKey, nonce) → cipherText + tag
4. Assemble envelope: [salt][nonce][cipherText+tag]
```

### Decrypt Flow

```
1. Parse salt(0..16), nonce(16..28), cipherAndTag(28..)
2. Derive same sub-key: PBKDF2(masterKey, salt, iterations)
3. AES-256-GCM decrypt(cipherAndTag, subKey, nonce) → plainData
   ↳ Throws VaultDecryptionException if GCM tag fails
```

### Example

```dart
final provider = AesGcmProvider(
  masterKey: await KeyManager.getOrCreateMasterKey('my-vault'),
  pbkdf2Iterations: 100000,
);
final cipher = await provider.encrypt(plainBytes);
final plain  = await provider.decrypt(cipher);
```

---

## 3. `aes_cbc_provider.dart` — AES-256-CBC

Compatibility provider for systems that cannot use GCM. **No integrity check** — a tampered ciphertext silently produces garbage plaintext.

### Security Properties

| Property | Detail |
|---|---|
| Algorithm | AES-256-CBC with PKCS7 padding |
| IV | 16-byte cryptographically random per call |
| Key | 32-byte key used directly (no PBKDF2 per call) |
| Integrity | **None** — use `AesGcmProvider` when integrity matters |
| `supportsIntegrityCheck` | `false` |

### Envelope Layout

```
Offset  Size     Field
──────  ───────  ──────────────────
0       16 bytes IV (random per call)
16      N bytes  PKCS7-padded ciphertext
```

### Constructor

```dart
AesCbcProvider({required Uint8List key})  // Throws VaultConfigException if key ≠ 32 bytes
```

### When to Use CBC

- Interoperability with external AES-CBC systems
- Legacy data migration (read old CBC, re-encrypt with GCM)
- `VaultConfig.light()` profile where speed matters more than integrity

---

## 4. `no_encryption_provider.dart` — No Encryption

Pass-through provider that returns data unchanged. Used by `VaultConfig.debug()` and `VaultConfig.maxPerformance()`.

```dart
class NoEncryptionProvider extends EncryptionProvider {
  const NoEncryptionProvider();
  String get algorithmName => 'None';
  int get headerFlag => EncryptionFlag.none;
  bool get supportsIntegrityCheck => false;
  Future<Uint8List> encrypt(Uint8List d) async => d;
  Future<Uint8List> decrypt(Uint8List d) async => d;
}
```

---

## 5. `encryption_factory.dart` — `EncryptionFactory`

Resolves the correct `EncryptionProvider` from config and a master key.

```dart
class EncryptionFactory {
  /// Creates provider from config + raw master key bytes.
  static Future<EncryptionProvider> create(
    EncryptionConfig config,
    Uint8List masterKey,
  ) async;

  /// Creates provider from config + password string (runs PBKDF2 internally).
  static Future<EncryptionProvider> fromPassword(
    EncryptionConfig config,
    Uint8List masterKey, {
    int iterations = 100000,
  }) async;
}
```

Resolution logic:

```
SensitivityLevel.none      → NoEncryptionProvider
SensitivityLevel.standard  → AesCbcProvider(key: masterKey)
SensitivityLevel.high
SensitivityLevel.selective → AesGcmProvider(masterKey, pbkdf2Iterations)
```

---

## 6. `key_manager.dart` — `KeyManager`

Static utility for all cryptographic key operations.

### Key Generation

```dart
// Generate a fresh 256-bit random key
Uint8List key = KeyManager.generateMasterKey();

// Generate N random bytes
Uint8List salt = KeyManager.generateRandom(16);
```

### PBKDF2 Key Derivation

```dart
Uint8List derivedKey = await KeyManager.deriveKeyFromPassword(
  password: 'user-passphrase',
  salt: salt,                      // 16+ byte random salt
  iterations: 100000,              // Higher = slower but stronger
);
// Returns 32 bytes (256 bits)
```

### Secure Key Storage (flutter_secure_storage)

```dart
// Store a key under a named ID
await KeyManager.storeKey('vault-key-1', keyBytes);

// Retrieve it
Uint8List? key = await KeyManager.retrieveKey('vault-key-1');

// Delete
await KeyManager.deleteKey('vault-key-1');

// Check existence
bool exists = await KeyManager.keyExists('vault-key-1');
```

### Master Key Lifecycle

```dart
// Recommended entry point: get existing or create new
Uint8List masterKey = await KeyManager.getOrCreateMasterKey('my-vault');
```

### Key Rotation

```dart
// Step 1: Begin rotation (generates new key, stores under temp ID)
KeyRotationResult rotation = await KeyManager.rotateKey('vault-key-1');

// Step 2a: Re-encrypt all data with rotation.newKey, then commit
await KeyManager.commitRotation(rotation);

// Step 2b: If something fails, abort
await KeyManager.abortRotation(rotation);
```

### `KeyRotationResult`

```dart
class KeyRotationResult {
  final Uint8List oldKey;
  final Uint8List newKey;
  final String oldKeyId;
  final String newKeyId;      // Temporary ID for the new key during rotation
}
```

### Key Age Tracking

```dart
await KeyManager.storeKeyCreationDate('vault-key-1');
DateTime? created = await KeyManager.getKeyCreationDate('vault-key-1');
bool isDue = await KeyManager.isKeyRotationDue('vault-key-1', maxAgeDays: 90);
```

---

## 7. `key_rotation_scheduler.dart` — `KeyRotationScheduler`

Automates key rotation based on time, operation count, or byte volume.

### `KeyRotationPolicy`

```dart
class KeyRotationPolicy {
  final Duration? rotationInterval;     // Time-based rotation (e.g., 90 days)
  final int? maxEncryptOperations;      // Count-based (e.g., 1,000,000 ops)
  final int? maxBytesEncrypted;         // Volume-based (e.g., 10 GB)
  final bool reEncryptExisting;         // Re-encrypt all entries on rotation
  final int archiveSize;                // How many old key events to keep

  // Derived
  bool get isTimeBased;
  bool get isCountBased;
  bool get isSizeBased;
}
```

### `KeyRotationEvent`

```dart
class KeyRotationEvent {
  final int generation;              // Key generation number (increments on each rotation)
  final DateTime rotatedAt;
  final int entriesReEncrypted;
  final String reason;               // 'time_based', 'count_based', 'manual', etc.
}
```

### `KeyRotationScheduler`

```dart
final scheduler = KeyRotationScheduler(
  policy: KeyRotationPolicy(
    rotationInterval: Duration(days: 90),
    reEncryptExisting: true,
  ),
  keyProviderFactory: (generation) async {
    // Create/fetch the encryption provider for the new key generation
    return AesGcmProvider(masterKey: await generateNewKey(generation));
  },
);

await scheduler.initialize();
scheduler.start();   // Starts background check timer

// Track encryption usage
await scheduler.recordEncryptOperation(payloadBytes);

// Manual rotation
final event = await scheduler.rotateNow(reason: 'security-audit');

// Status
print(scheduler.currentGeneration);    // Current key generation
print(scheduler.isRotationDue);        // Boolean check
print(scheduler.history);              // List<KeyRotationEvent>

scheduler.stop();
await scheduler.dispose();
```

### Rotation Triggers

| Trigger | Policy Field | Description |
|---|---|---|
| Time-based | `rotationInterval` | Rotates after a fixed duration |
| Count-based | `maxEncryptOperations` | Rotates after N encrypt calls |
| Volume-based | `maxBytesEncrypted` | Rotates after N bytes encrypted |
| Manual | — | Calling `rotateNow()` directly |

### `typedef KeyProviderFactory`

```dart
typedef KeyProviderFactory =
  Future<EncryptionProvider> Function(int generation);
```

Implement this to vend the correct encryption provider for each key generation (e.g., fetch the new key from a KMS, store with `KeyManager.storeKey`).

---

## Algorithm Comparison

| | AES-256-GCM | AES-256-CBC | None |
|---|---|---|---|
| Confidentiality | ✅ | ✅ | ❌ |
| Integrity | ✅ (AEAD) | ❌ | ❌ |
| Key derivation | PBKDF2 per call | Key directly | — |
| Overhead/entry | 28 bytes header + 16 bytes tag | 16 bytes IV | 0 |
| Speed | Moderate | Fast | Fastest |
| Use case | Default, ERP, medical | Legacy compat | Debug, test |
