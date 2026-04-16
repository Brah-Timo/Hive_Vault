# Cache & Rate Limiter Layer

> **Files**: `lib/src/cache/`
>
> - `lru_cache.dart` — Generic LRU cache + `VaultCache` alias
> - `rate_limiter.dart` — Token-bucket, sliding-window, fixed-window, per-key, composite limiters

---

## 1. `lru_cache.dart`

### `LruCache<K, V>`

A generic, fixed-capacity Least-Recently-Used cache backed by a `LinkedHashMap` with access-order semantics.

```dart
class LruCache<K, V> {
  final int capacity;

  LruCache({required this.capacity});
}
```

### Core Operations

```dart
// Get a value (promotes to MRU position, records hit/miss)
V? get(K key);

// Store a value (evicts LRU entry if at capacity)
void put(K key, V value);

// Remove an entry
void remove(K key);

// Clear all entries + reset statistics
void clear();
```

### Query Helpers

```dart
// Peek without updating access order
bool containsKey(K key);

int  get length;       // Current entry count
bool get isEmpty;
Iterable<K> get keys;  // All keys in LRU order (oldest first)
```

### Statistics

```dart
int    get hits;       // Total hits since creation or last clear()
int    get misses;     // Total misses since creation or last clear()
int    get evictions;  // Total evictions since creation or last clear()
double get hitRatio;   // hits / (hits + misses), 0.0 if no accesses
```

### Implementation Detail

```dart
// Uses LinkedHashMap to maintain insertion/access order:
_map = LinkedHashMap<K, V>();

// On get():
//   1. _map.remove(key) → value  (removes from current position)
//   2. _map[key] = value          (re-inserts at tail = MRU position)

// On put() when full:
//   1. _map.remove(_map.keys.first)  (evict head = LRU position)
//   2. _map[key] = value              (insert at tail)
```

This gives O(1) amortised get/put/evict since `LinkedHashMap` operations are O(1).

### `VaultCache` Alias

```dart
typedef VaultCache = LruCache<String, dynamic>;

VaultCache createVaultCache(int capacity) => LruCache(capacity: capacity);
```

`HiveVaultImpl` uses `VaultCache` to cache decrypted, deserialized values so that repeated reads of the same key skip decryption and decompression.

### Tuning the Cache

```dart
// In VaultConfig:
VaultConfig(
  memoryCacheSize: 200,      // Entries to cache (default: 100)
  enableMemoryCache: true,   // Set false to disable entirely
)
```

Cache sizing guidelines:
| Use case | Recommended size |
|---|---|
| Embedded / low-memory | 30–50 |
| Standard mobile | 100 (default) |
| ERP / tablets | 200 |
| Desktop / server | 500–1000 |

---

## 2. `rate_limiter.dart`

### Overview

Three rate limiting algorithms are provided, plus a composite `VaultRateLimiter`:

| Class | Algorithm | Burst allowance | Use case |
|---|---|---|---|
| `TokenBucket` | Token bucket | Yes (up to `capacity`) | Default limiter |
| `SlidingWindowLimiter` | Sliding window | No | Strict per-window limits |
| `FixedWindowLimiter` | Fixed window | No | Simple per-second/minute |
| `PerKeyRateLimiter` | Per-key token buckets | Yes | Per-entity throttling |
| `VaultRateLimiter` | Composite (per op type) | Yes | Full vault throttling |

---

### `TokenBucket`

```dart
class TokenBucket {
  final double capacity;     // Max burst size (tokens)
  final double refillRate;   // Tokens added per second

  TokenBucket({required this.capacity, required this.refillRate});
}
```

Tokens refill continuously (virtual refill on each operation). Burst up to `capacity`.

```dart
final bucket = TokenBucket(capacity: 100, refillRate: 50);

// Non-blocking check
bool allowed = bucket.tryConsume();       // cost = 1.0
bool allowed = bucket.tryConsume(cost: 5.0);

// Blocking (throws on exceed)
bucket.consume(cost: 1.0);               // Throws RateLimitExceededException

// Async wait
await bucket.consumeAsync(cost: 1.0);   // Waits until tokens available

// Status
double tokens = bucket.availableTokens;
double remaining = bucket.remainingCapacity;

// Reset
bucket.refillFull();
```

---

### `SlidingWindowLimiter`

```dart
class SlidingWindowLimiter {
  final int maxRequests;
  final Duration window;
}
```

Maintains a list of request timestamps. The window slides forward in real time — no burst allowance.

```dart
final limiter = SlidingWindowLimiter(maxRequests: 100, window: Duration(seconds: 1));
bool allowed = limiter.tryAcquire();
limiter.acquire();   // Throws if limit exceeded

int count = limiter.currentCount;
double util = limiter.utilizationRatio;
```

---

### `FixedWindowLimiter`

```dart
class FixedWindowLimiter {
  final int maxRequests;
  final Duration window;
}
```

Counter resets at the start of each window period. Simplest implementation but allows 2× burst at window boundaries.

```dart
final limiter = FixedWindowLimiter(maxRequests: 100, window: Duration(seconds: 1));
bool allowed = limiter.tryAcquire();
limiter.acquire();   // Throws if limit exceeded

int remaining = limiter.remaining;
```

---

### `PerKeyRateLimiter`

Maintains a separate `TokenBucket` per key, with automatic eviction of stale buckets.

```dart
final perKey = PerKeyRateLimiter(
  capacity: 10,
  refillRate: 5,
  bucketTtl: Duration(minutes: 10),
  maxBuckets: 10000,
);

bool allowed = perKey.tryConsume('user:123');
perKey.consume('user:123');   // Throws if limit exceeded

int active = perKey.activeBuckets;
```

---

### `VaultRateLimiter` — Composite Limiter

Separate token buckets for each operation type:

```dart
class VaultRateLimiter {
  final TokenBucket? writeLimit;
  final TokenBucket? readLimit;
  final TokenBucket? searchLimit;
  final TokenBucket? deleteLimit;
}
```

Pre-built profiles:

```dart
// Standard: 1000 writes/s, 5000 reads/s, 100 searches/s
final limiter = VaultRateLimiter.standard();

// Mobile: 50 writes/s, 200 reads/s, 10 searches/s
final limiter = VaultRateLimiter.mobile();
```

Usage:

```dart
limiter.checkWrite();    // Throws RateLimitExceededException if bucket empty
limiter.checkRead();
limiter.checkSearch();
limiter.checkDelete();

// Inspect violations
List<String> violations = limiter.violations;
int count = limiter.violationCount;
```

---

### `RateLimitExceededException`

```dart
class RateLimitExceededException extends VaultException {
  const RateLimitExceededException(String message, {Object? cause});
}
```

Extends `VaultException` so it integrates with the standard error handling pattern.

---

## Cache + Rate Limiter Integration

In `HiveVaultImpl`, the cache is checked before the rate limiter — cache hits don't consume rate limit tokens:

```dart
// Pseudo-code for secureGet:
if (_cache != null) {
  final cached = _cache!.get(key);
  if (cached != null) {
    _audit.log(action: AuditAction.cacheHit, ...);
    return cached as T?;  // No rate limit consumed
  }
}
// Cache miss → rate limiter check → box.get() → decrypt → ...
```
