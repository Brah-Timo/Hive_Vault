# TTL (Time-To-Live) Manager

> **File**: `lib/src/impl/ttl_manager.dart`

Manages per-key expiration metadata, allowing entries to automatically expire after a specified duration.

---

## Overview

TTL metadata is stored in a **dedicated Hive box** (separate from the data box) named `__ttl_<boxName>__`. Values are stored as integer milliseconds-since-epoch timestamps.

Expiry is handled in two ways:
1. **Lazy eviction**: `isExpired(key)` is checked on each read — expired entries can be deleted
2. **Active purge**: `startAutoPurge()` runs a periodic sweep that calls `onExpired` for each expired key

---

## `TtlManager`

```dart
class TtlManager {
  final String dataBoxName;

  TtlManager({required this.dataBoxName});

  String get _ttlBoxName => '__ttl_${dataBoxName}__';
}
```

### Lifecycle

```dart
// Open the TTL metadata box
await ttlManager.initialize();

// Close the TTL box and stop any purge timer
await ttlManager.close();
```

---

## Setting / Clearing TTL

```dart
// Set an expiry for a key
await ttlManager.setExpiry('SESSION-abc123', Duration(hours: 24));

// Set zero duration → removes TTL (entry never expires)
await ttlManager.setExpiry('PERM-KEY', Duration.zero);

// Remove TTL explicitly
await ttlManager.clearExpiry('SESSION-abc123');
```

---

## Checking Expiry

```dart
// Is this key expired?
bool expired = ttlManager.isExpired('SESSION-abc123');

// When does this key expire? (null = no TTL set)
DateTime? expiry = ttlManager.getExpiry('SESSION-abc123');

// How much time remains? (null = no TTL, Duration.zero = already expired)
Duration? remaining = ttlManager.getRemaining('SESSION-abc123');
```

---

## Scanning Expired / Active Keys

```dart
// Keys whose TTL has passed
Iterable<String> expired = ttlManager.expiredKeys();

// Keys with an active (non-expired) TTL
Iterable<String> active = ttlManager.activeKeys();
```

---

## Auto-Purge

Starts a `Timer.periodic` that runs `onExpired` for each expired key at the specified interval:

```dart
ttlManager.startAutoPurge(
  interval: Duration(minutes: 5),
  onExpired: (key) async {
    await vault.secureDelete(key);        // Delete the actual vault entry
    print('Expired key deleted: $key');
  },
);

// Stop the purge timer
ttlManager.stopAutoPurge();
```

The purge callback is:
- Called for each expired key independently
- Wrapped in try/catch — one failure doesn't stop other keys from being purged
- Followed by `clearExpiry(key)` to remove the TTL metadata

---

## Manual Purge Sweep

```dart
final deletedKeys = await ttlManager.purgeNow(
  onExpired: (key) async {
    await vault.secureDelete(key);
  },
);
print('Purged ${deletedKeys.length} expired entries');
```

---

## Usage Example

```dart
final vault = await HiveVault.open(boxName: 'sessions', config: VaultConfig());
final ttl = TtlManager(dataBoxName: 'sessions');
await ttl.initialize();

// Store a session token with 1-hour TTL
await vault.secureSave('SESSION-abc123', {'userId': 'U-001', 'token': 'xyz'});
await ttl.setExpiry('SESSION-abc123', Duration(hours: 1));

// Check on read
Future<Map?> getSession(String id) async {
  if (ttl.isExpired(id)) {
    await vault.secureDelete(id);
    await ttl.clearExpiry(id);
    return null;  // Session expired
  }
  return vault.secureGet<Map>(id);
}

// Start background purge every 10 minutes
ttl.startAutoPurge(
  interval: Duration(minutes: 10),
  onExpired: (key) => vault.secureDelete(key),
);
```

---

## TTL Storage Format

Each entry in the `__ttl_<boxName>__` box:

```
key   → int (Unix timestamp in milliseconds)
"SESSION-abc123" → 1710511200000  (2024-03-15 16:00:00 UTC)
```

No encryption is applied to the TTL box itself — only expiry timestamps are stored (not values).

---

## Integration with HiveVaultImpl

`TtlManager` is an optional addon — it is NOT wired into `HiveVaultImpl` by default. You must create and manage it alongside the vault:

```dart
// Pattern: lazy expiry check on every read
class SessionRepository {
  final SecureStorageInterface _vault;
  final TtlManager _ttl;

  Future<Map?> get(String sessionId) async {
    if (_ttl.isExpired(sessionId)) {
      await _vault.secureDelete(sessionId);
      await _ttl.clearExpiry(sessionId);
      return null;
    }
    return _vault.secureGet<Map>(sessionId);
  }

  Future<void> save(String id, Map data, Duration ttl) async {
    await _vault.secureSave(id, data);
    await _ttl.setExpiry(id, ttl);
  }
}
```
