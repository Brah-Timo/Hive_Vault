# Sharding Layer

> **File**: `lib/src/sharding/shard_manager.dart`

Horizontally partitions vault data across multiple Hive boxes (shards) for managing large datasets and domain isolation.

---

## Why Sharding?

| Problem | Solution |
|---|---|
| Single Hive box grows too large (practical limit ~100 MB on mobile) | Split across multiple boxes |
| All modules share one encryption key | Per-shard encryption key |
| Compaction blocks all reads | Compact individual shards independently |
| Single box is a single point of failure | Isolate failures to one shard |

---

## Routing Strategies

### `ShardRoutingStrategy` (Abstract)

```dart
abstract class ShardRoutingStrategy {
  int route(String key, int shardCount);
  String get name;
}
```

### `ConsistentHashStrategy` (Default)

```dart
class ConsistentHashStrategy implements ShardRoutingStrategy {
  String get name => 'consistent_hash';

  // DJB2-inspired polynomial hash for even key distribution
  int route(String key, int shardCount) {
    int hash = 5381;
    for (final rune in key.runes) {
      hash = ((hash << 5) + hash) ^ rune;
      hash &= 0x7FFFFFFF;
    }
    return hash % shardCount;
  }
}
```

Best for: uniform key distribution across shards.

### `PrefixRoutingStrategy`

Routes keys to specific shards based on their prefix:

```dart
final strategy = PrefixRoutingStrategy({
  'user:':    0,   // All user keys → shard 0
  'order:':   1,   // All order keys → shard 1
  'product:': 2,   // All product keys → shard 2
}, defaultShard: 3);  // Everything else → shard 3
```

Best for: domain-based isolation where you want to co-locate related records.

### `ModuloStrategy`

Uses the trailing numeric portion of a key:

```dart
// Key "INVOICE-0042" → 42 % shardCount
// Key "CLIENT-007"   → 7 % shardCount
// Key "abc"          → sum of char codes % shardCount (fallback)
```

Best for: numeric-suffix keys with predictable shard assignment.

### `CustomRoutingStrategy`

```dart
final strategy = CustomRoutingStrategy(
  (key, shardCount) {
    // Your custom logic
    return key.hashCode.abs() % shardCount;
  },
  name: 'my_custom',
);
```

---

## `ShardDescriptor`

Metadata about a single shard:

```dart
class ShardDescriptor {
  final int index;
  final String boxName;
  final SecureStorageInterface vault;
}
```

---

## `ShardManager`

The main class that manages the shard collection and routes operations.

```dart
class ShardManager implements SecureStorageInterface {
  final int shardCount;
  final ShardRoutingStrategy strategy;
  final VaultConfig defaultConfig;
  final Map<int, VaultConfig> shardConfigs;
  final String namePrefix;       // Shard boxes: "${namePrefix}_0", "_1", etc.

  ShardManager({
    required this.shardCount,
    this.strategy = const ConsistentHashStrategy(),
    required this.defaultConfig,
    this.shardConfigs = const {},
    this.namePrefix = 'shard',
  });
}
```

### Lifecycle

```dart
// Open all shards
await shardManager.initialize();

// Close all shards
await shardManager.close();
```

### Routing

```dart
// Find which shard a key belongs to
ShardDescriptor desc = shardManager.shardFor('ORDER-001');
print('ORDER-001 → shard ${desc.index} (box: ${desc.boxName})');
```

### `SecureStorageInterface` Implementation

`ShardManager` implements `SecureStorageInterface` — it transparently routes each operation to the correct shard:

```dart
// secureSave routes to the correct shard automatically
await shardManager.secureSave('ORDER-001', orderData);

// secureGet transparently reads from the correct shard
final order = await shardManager.secureGet<Map>('ORDER-001');

// getAllKeys aggregates from all shards
final allKeys = await shardManager.getAllKeys();

// secureSearch searches all shards and merges results
final results = await shardManager.secureSearch<Map>('invoice');
```

### Per-Shard Operations

```dart
// Get statistics for a specific shard
VaultStats stats = await shardManager.getShardStats(shardIndex: 2);

// Compact a single shard (non-blocking for other shards)
await shardManager.compactShard(shardIndex: 1);

// Rebuild index for a single shard
await shardManager.rebuildShardIndex(shardIndex: 0);
```

### Cross-Shard Search

Search is performed against all shards in parallel and results are merged:

```dart
// Internally:
final futures = _shards.map((shard) => shard.vault.secureSearch<T>(query));
final allResults = await Future.wait(futures);
return allResults.expand((r) => r).toList();
```

---

## Setup Example

```dart
final shardManager = ShardManager(
  shardCount: 4,
  namePrefix: 'erp_data',
  defaultConfig: VaultConfig.erp(),
  shardConfigs: {
    // Shard 0 gets extra cache (high-traffic client data)
    0: VaultConfig.erp().copyWith(memoryCacheSize: 500),
  },
  strategy: PrefixRoutingStrategy({
    'CLI-':  0,    // Clients → shard 0 (most accessed)
    'INV-':  1,    // Invoices → shard 1
    'PROD-': 2,    // Products → shard 2
    'PAY-':  3,    // Payments → shard 3
  }),
);

await shardManager.initialize();

// Works exactly like a regular vault
await shardManager.secureSave('CLI-001', client, searchableText: 'ACME Corp');
final client = await shardManager.secureGet<Map>('CLI-001');
```

---

## Shard Key Distribution

With `ConsistentHashStrategy` and 4 shards, a typical ERP dataset distributes as:

| Shard | Expected % | Key range |
|---|---|---|
| 0 | ~25% | hash % 4 == 0 |
| 1 | ~25% | hash % 4 == 1 |
| 2 | ~25% | hash % 4 == 2 |
| 3 | ~25% | hash % 4 == 3 |

With `PrefixRoutingStrategy`, distribution depends on your key structure — use consistent prefixes for predictable routing.
