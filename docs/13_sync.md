# Sync Layer

> **Files**: `lib/src/sync/`
>
> - `vault_synchronizer.dart` — Bidirectional sync engine + `RemoteDataSource` + `SyncConfig` + `SyncResult`
> - `conflict_resolver.dart` — Conflict resolution strategies

---

## 1. `conflict_resolver.dart`

### `VersionedValue<T>`

Wraps a value with versioning metadata:

```dart
class VersionedValue<T> {
  final T value;
  final String sourceId;    // e.g., 'local', 'remote', 'node-42'
  final DateTime timestamp;
  final int version;        // Monotonic version number
}
```

### `VaultConflict<T>`

Represents a conflict between local and remote versions of the same key:

```dart
class VaultConflict<T> {
  final String key;
  final VersionedValue<T> local;
  final VersionedValue<T> remote;
}
```

### `ResolutionStrategy`

```dart
enum ResolutionStrategy {
  localWins,
  remoteWins,
  merged,     // Field-level merge
  deferred,   // Human review required
  custom,
}
```

### `ConflictResolution<T>`

```dart
class ConflictResolution<T> {
  final String key;
  final T resolvedValue;
  final ResolutionStrategy strategy;
}
```

### `ConflictResolver<T>` (Abstract)

```dart
abstract class ConflictResolver<T> {
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict);
}
```

---

### Built-in Resolvers

#### `LastWriteWinsResolver<T>`

```dart
class LastWriteWinsResolver<T> implements ConflictResolver<T> {
  const LastWriteWinsResolver();
  // Chooses the value with the later timestamp
  // local.timestamp > remote.timestamp → local wins
  // otherwise → remote wins
}
```

#### `FirstWriteWinsResolver<T>`

```dart
class FirstWriteWinsResolver<T> implements ConflictResolver<T> {
  const FirstWriteWinsResolver();
  // Chooses the value with the earlier timestamp (preserves original)
}
```

#### `RemoteWinsResolver<T>`

```dart
class RemoteWinsResolver<T> implements ConflictResolver<T> {
  const RemoteWinsResolver();
  // Always chooses the remote value
  // Use for: read-only sync where remote is the source of truth
}
```

#### `LocalWinsResolver<T>`

```dart
class LocalWinsResolver<T> implements ConflictResolver<T> {
  const LocalWinsResolver();
  // Always chooses the local value
  // Use for: offline-first apps where local edits take priority
}
```

#### `FieldMergeResolver`

For `Map<String, dynamic>` records, merges non-conflicting fields:

```dart
class FieldMergeResolver implements ConflictResolver<Map<String, dynamic>> {
  final ResolutionStrategy scalarResolution;   // What to do for scalar conflicts
  final Set<String> localPriorityFields;       // These fields always take local value
  final Set<String> remotePriorityFields;      // These fields always take remote value

  FieldMergeResolver({
    this.scalarResolution = ResolutionStrategy.remoteWins,
    this.localPriorityFields = const {},
    this.remotePriorityFields = const {},
  });
}
```

Example: a client record where local has updated the `phone` and remote has updated the `email`:

```
local:  {"name": "ACME", "phone": "+1-555-0101", "email": "old@acme.com"}
remote: {"name": "ACME", "phone": "+1-555-0000", "email": "new@acme.com"}

FieldMergeResolver(localPriorityFields: {'phone'}, remotePriorityFields: {'email'})
→ {"name": "ACME", "phone": "+1-555-0101", "email": "new@acme.com"}
```

#### `VersionVectorResolver<T>`

Uses monotonic version numbers to determine which write happened later. Falls back to a secondary resolver when versions are equal:

```dart
class VersionVectorResolver<T> implements ConflictResolver<T> {
  final ConflictResolver<T> _fallback;

  VersionVectorResolver({ConflictResolver<T>? fallback})
  // Default fallback: LastWriteWinsResolver
}
```

#### `DeferredResolver<T>`

Queues conflicts for later human review:

```dart
class DeferredResolver<T> implements ConflictResolver<T> {
  final List<VaultConflict<T>> _queue;

  // Returns remote value immediately (provisional resolution)
  // Queues the conflict for human review
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict);

  // Access the queue for UI review
  List<VaultConflict<T>> get pending;
  void clearResolved(String key);
}
```

#### `CustomResolver<T>`

```dart
class CustomResolver<T> implements ConflictResolver<T> {
  CustomResolver(
    Future<ConflictResolution<T>> Function(VaultConflict<T>) handler,
  );
}
```

#### `ConflictDetector<T>` (Utility)

```dart
class ConflictDetector<T> {
  static List<VaultConflict<T>> detect<T>({
    required Map<String, VersionedValue<T>> existing,
    required Map<String, VersionedValue<T>> incoming,
  });
  // Returns conflicts: keys where both sides have different values
}
```

---

## 2. `vault_synchronizer.dart`

### `RemoteDataSource` (Abstract)

Implement this interface to connect to any remote backend:

```dart
abstract class RemoteDataSource {
  /// Fetch entries modified since [cursor] (epoch ms, 0 = full sync).
  Future<Map<String, String>> fetchSince(int cursor);

  /// Push [entries] (key → JSON string) to remote.
  Future<void> push(Map<String, String> entries);

  /// Delete [keys] from remote.
  Future<void> deleteKeys(List<String> keys);

  /// Get the current remote cursor (epoch ms of latest change).
  Future<int> getRemoteCursor();
}
```

### `SyncConfig`

```dart
class SyncConfig {
  final bool enablePeriodicSync;            // Default: false
  final Duration syncInterval;              // Default: 15 minutes
  final int maxConflictRetries;             // Default: 3
  final bool syncDeletes;                   // Default: true
  final int batchSize;                      // Default: 500 entries per push batch
}
```

### `SyncResult`

```dart
class SyncResult {
  final DateTime startedAt;
  final DateTime completedAt;
  final int pulled;              // New entries saved from remote
  final int pushed;              // Local entries sent to remote
  final int conflicts;           // Conflicts detected
  final int resolved;            // Conflicts resolved
  final int errors;              // Non-fatal errors
  final List<String> errorDetails;
  final int newCursor;           // Updated sync cursor
  final bool success;            // true if errors == 0

  Duration get elapsed;
}
```

### `VaultSynchronizer<T>`

```dart
class VaultSynchronizer<T> {
  VaultSynchronizer({
    required SecureStorageInterface local,
    required RemoteDataSource remote,
    required ConflictResolver<T> resolver,
    SyncConfig config = const SyncConfig(),
  });
}
```

### Lifecycle

```dart
await sync.initialize();       // Opens internal metadata box (sync cursor)
sync.startPeriodicSync();      // Starts background Timer
sync.stopPeriodicSync();       // Cancels Timer
await sync.dispose();          // Stops timer, closes streams
```

### Manual Sync

```dart
final result = await sync.syncNow();
print(result);
// SyncResult(pulled: 42, pushed: 15, conflicts: 3, resolved: 3, errors: 0, elapsed: 1247ms)
```

### Event Stream

```dart
// Sync event types
enum SyncEventType { started, progress, conflictDetected, completed, failed }

// Subscribe to events
sync.events.listen((event) {
  switch (event.type) {
    case SyncEventType.conflictDetected:
      print('Conflict on key: ${event.data['key']}');
    case SyncEventType.completed:
      print('Sync complete: ${event.message}');
    // ...
  }
});

// Subscribe to results
sync.results.listen((result) {
  print('Sync finished: pulled=${result.pulled} pushed=${result.pushed}');
});
```

### Status

```dart
bool isSyncing = sync.isSyncing;
int lastCursor = sync.lastSyncCursor;
```

---

## Sync Protocol

```
┌─────────┐  fetchSince(cursor)  ┌──────────┐
│  Local  │ ─────────────────── →│  Remote  │
│  Vault  │ ← ──────────────────  │   API    │
└─────────┘  remoteEntries       └──────────┘

For each remote entry:
  - Not in local → secureSave locally (pull)
  - Different from local → resolve conflict → secureSave locally

Push local keys to remote (if cursor > 0):
  - Serialize all local values as JSON
  - remote.push(entries) in batches of batchSize

Persist new cursor:
  - newCursor = remote.getRemoteCursor()
  - Save to '__sync_meta__' Hive box
```

---

## Example: REST Backend Integration

```dart
class RestRemoteDataSource implements RemoteDataSource {
  final String baseUrl;
  final http.Client _client;

  @override
  Future<Map<String, String>> fetchSince(int cursor) async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/entries?since=$cursor'),
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, jsonEncode(v)));
  }

  @override
  Future<void> push(Map<String, String> entries) async {
    await _client.post(
      Uri.parse('$baseUrl/entries'),
      body: jsonEncode(entries),
      headers: {'Content-Type': 'application/json'},
    );
  }

  @override
  Future<void> deleteKeys(List<String> keys) async {
    await _client.delete(
      Uri.parse('$baseUrl/entries'),
      body: jsonEncode({'keys': keys}),
    );
  }

  @override
  Future<int> getRemoteCursor() async {
    final resp = await _client.get(Uri.parse('$baseUrl/cursor'));
    return int.parse(resp.body);
  }
}

// Usage
final sync = VaultSynchronizer<Map<String, dynamic>>(
  local: vault,
  remote: RestRemoteDataSource(baseUrl: 'https://api.example.com/v1/vault'),
  resolver: LastWriteWinsResolver(),
  config: SyncConfig(
    enablePeriodicSync: true,
    syncInterval: Duration(minutes: 5),
    batchSize: 200,
  ),
);

await sync.initialize();
sync.startPeriodicSync();
```
