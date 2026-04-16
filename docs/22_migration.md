# Schema Migration Manager

> **File**: `lib/src/impl/migration_manager.dart`

Provides versioned binary payload migrations for upgrading existing vault data when the payload format changes between HiveVault releases.

---

## Overview

When HiveVault's binary payload format changes (e.g., a new header field is added, encryption scheme changes), existing data must be migrated. `MigrationManager` runs a chain of `VaultMigration` steps in version order.

---

## `VaultMigration` (Abstract)

```dart
abstract class VaultMigration {
  int get fromVersion;                            // Reads this payload version
  int get toVersion;                              // Produces this payload version
  Future<Uint8List> migrate(Uint8List oldPayload); // Transform the bytes
  String get description;                         // Human-readable description
}
```

---

## `MigrationManager`

```dart
class MigrationManager {
  const MigrationManager(List<VaultMigration> migrations);
}
```

### Version Storage

Schema versions are persisted in a dedicated Hive box:

```
Box name : '__hive_vault_schema__'
Key      : 'schema_version'
Value    : int
```

### Static Methods

```dart
// Read the current version from disk (returns 0 if never migrated)
static Future<int> getCurrentVersion() async;

// Persist the new version
static Future<void> setCurrentVersion(int version) async;
```

### `migrate`

```dart
Future<void> migrate(
  Box<Uint8List> box,
  int currentVersion,
  int targetVersion,
) async
```

Execution:
1. Filter migrations: `fromVersion >= currentVersion && toVersion <= targetVersion`
2. Sort by `fromVersion` ascending
3. For each migration:
   - Loop over all keys in the box
   - Call `migration.migrate(payload)` on each entry
   - `box.put(key, migratedPayload)` — in-place update
   - `setCurrentVersion(migration.toVersion)` — checkpoint after each migration
4. Throws `VaultStorageException` if any single entry fails

**Checkpoint behavior**: If migration fails halfway through, the schema version is set to the last fully-completed migration. Re-running will continue from where it left off.

---

## Implementing a Migration

### Example: Adding a checksum field (v1 → v2)

```dart
class AddChecksumMigration extends VaultMigration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  String get description => 'Add SHA-256 checksum to payload v1 → v2';

  @override
  Future<Uint8List> migrate(Uint8List oldPayload) async {
    // Old format: [version(1)][compFlag(1)][encFlag(1)][dataLen(4)][data]
    // New format: [version(1)][compFlag(1)][encFlag(1)][dataLen(4)][data][checksum(32)]

    final dataLen = ByteData.view(oldPayload.buffer)
        .getUint32(3, Endian.big);
    final data = oldPayload.sublist(7, 7 + dataLen);

    // Compute checksum
    final hash = await Sha256().hash(data);
    final checksum = Uint8List.fromList(hash.bytes);

    // Build new payload
    final newPayload = Uint8List(oldPayload.length + 32);
    newPayload.setRange(0, oldPayload.length, oldPayload);
    newPayload.setRange(oldPayload.length, newPayload.length, checksum);

    // Update version byte
    newPayload[0] = 2;

    return newPayload;
  }
}
```

---

## Running Migrations at App Startup

```dart
Future<void> initializeVault() async {
  await HiveVault.initHive();

  // Check current schema version
  final currentVersion = await MigrationManager.getCurrentVersion();
  const targetVersion = 2;

  if (currentVersion < targetVersion) {
    // Open raw box for migration
    final box = await Hive.openBox<Uint8List>('my_vault');

    final manager = MigrationManager([
      AddChecksumMigration(),
      // Add future migrations here
    ]);

    await manager.migrate(box, currentVersion, targetVersion);
    await box.close();
  }

  // Now open the vault normally (will use new format)
  final vault = await HiveVault.open(
    boxName: 'my_vault',
    config: VaultConfig(),
  );
}
```

---

## Migration Console Output

```
HiveVault: running 2 migration(s) v0 → v2
  → Add SHA-256 checksum to payload v1 → v2
  ✅ Migration to v2 complete
  → Re-key to AES-256-GCM v2 → v3
  ✅ Migration to v3 complete
```

---

## Safety Notes

1. **Backup first**: Always backup the `.hive` file before running migrations on production data.
2. **Idempotency**: Migrations should be safe to run multiple times (checksum already present → no-op).
3. **Error recovery**: A failed migration leaves the box partially migrated. The schema version is saved after each completed migration, so re-running resumes safely.
4. **Testing**: Test each migration in isolation with synthetic data before deploying.
