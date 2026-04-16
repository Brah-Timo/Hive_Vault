# Rate Limiter Reference

> **File**: `lib/src/cache/rate_limiter.dart`

Full technical reference for all rate limiting classes provided by HiveVault.

---

## Token Bucket Algorithm

```
┌─────────────────────────────────┐
│         Token Bucket            │
│                                 │
│  capacity = 100                 │
│  refillRate = 50 tokens/sec     │
│                                 │
│  At t=0:   tokens = 100  ████   │  Full
│  Burst 80: tokens = 20   ██     │  Low
│  At t=1s:  tokens = 70   ███████│  Refilled
│                                 │
└─────────────────────────────────┘
```

- Tokens fill at `refillRate` per second, up to `capacity`
- Burst operations consume tokens immediately
- `tryConsume()` fails if insufficient tokens (no wait)
- `consumeAsync()` waits until tokens are available

---

## `TokenBucket`

```dart
class TokenBucket {
  final double capacity;    // Max burst size
  final double refillRate;  // Tokens/second

  TokenBucket({required this.capacity, required this.refillRate});
}
```

### Methods

| Method | Description | Throws |
|---|---|---|
| `tryConsume({double cost = 1.0})` | Returns `true` if tokens available and consumed | No |
| `consume({double cost = 1.0})` | Consumes or throws | `RateLimitExceededException` |
| `consumeAsync({double cost = 1.0})` | Waits until tokens available | No |
| `refillFull()` | Instantly fills bucket to capacity | No |
| `availableTokens` | Current token count (after virtual refill) | — |
| `remainingCapacity` | capacity - availableTokens | — |

### Virtual Refill

Tokens are NOT added by a timer. Instead, `_refill()` is called at the start of every operation and computes how many tokens should have accumulated since the last access:

```dart
void _refill() {
  final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;  // seconds
  final newTokens = elapsed * refillRate;
  _tokens = (_tokens + newTokens).clamp(0.0, capacity);
  _lastRefill = now;
}
```

This gives O(1) time complexity with no background timer needed.

---

## `SlidingWindowLimiter`

Rolling window counter. No burst allowance — hard limit per window.

```dart
class SlidingWindowLimiter {
  final int maxRequests;
  final Duration window;
}
```

| Method | Description |
|---|---|
| `tryAcquire()` | Returns `true` if under limit (and records timestamp) |
| `acquire()` | Acquires or throws `RateLimitExceededException` |
| `currentCount` | Number of requests in the current window |
| `utilizationRatio` | `currentCount / maxRequests` |

**Implementation**: Maintains a `List<DateTime>`. On each call, removes timestamps older than `window`, then checks if `length < maxRequests`.

---

## `FixedWindowLimiter`

Resets counter at the start of each window period. Simple but allows 2× burst at window boundaries.

```dart
class FixedWindowLimiter {
  final int maxRequests;
  final Duration window;
}
```

| Method | Description |
|---|---|
| `tryAcquire()` | Returns `true` if under limit |
| `acquire()` | Acquires or throws |
| `remaining` | Remaining requests in the current window |

---

## `PerKeyRateLimiter`

A map of `TokenBucket` instances, one per key. Stale buckets are automatically evicted.

```dart
class PerKeyRateLimiter {
  final double capacity;
  final double refillRate;
  final Duration bucketTtl;     // Evict buckets idle for this duration
  final int maxBuckets;         // Maximum concurrent buckets

  PerKeyRateLimiter({
    required this.capacity,
    required this.refillRate,
    this.bucketTtl = const Duration(minutes: 10),
    this.maxBuckets = 10000,
  });
}
```

| Method | Description |
|---|---|
| `tryConsume(key)` | Try to consume 1 token for this key |
| `consume(key)` | Consume or throw |
| `activeBuckets` | Number of currently active key buckets |

**Eviction**: `_evictStale()` is called when `_buckets.length >= maxBuckets`. It removes all buckets where `lastAccess` is older than `bucketTtl`.

---

## `VaultRateLimiter` (Composite)

Separate token buckets for each vault operation type.

```dart
class VaultRateLimiter {
  final TokenBucket? writeLimit;
  final TokenBucket? readLimit;
  final TokenBucket? searchLimit;
  final TokenBucket? deleteLimit;
}
```

### Pre-built Profiles

```dart
// Standard: high throughput desktop/server
VaultRateLimiter.standard()
// → writeLimit:  capacity=1000, refillRate=1000/s
// → readLimit:   capacity=5000, refillRate=5000/s
// → searchLimit: capacity=100,  refillRate=100/s
// → deleteLimit: capacity=500,  refillRate=500/s

// Mobile: battery-conscious limits
VaultRateLimiter.mobile()
// → writeLimit:  capacity=100, refillRate=50/s
// → readLimit:   capacity=500, refillRate=200/s
// → searchLimit: capacity=20,  refillRate=10/s
// → deleteLimit: capacity=100, refillRate=50/s
```

### Usage

```dart
final limiter = VaultRateLimiter.standard();

// Call before each operation
limiter.checkWrite();    // consume from writeLimit
limiter.checkRead();     // consume from readLimit
limiter.checkSearch();   // consume from searchLimit
limiter.checkDelete();   // consume from deleteLimit

// Violation tracking
print('Total violations: ${limiter.violationCount}');
limiter.violations.forEach(print);  // Each: "write @ 2024-03-15T..."
```

---

## `RateLimitExceededException`

```dart
class RateLimitExceededException extends VaultException {
  const RateLimitExceededException(String message, {Object? cause});
}
```

Catch it specifically or via `VaultException`:

```dart
try {
  limiter.checkWrite();
  await vault.secureSave(key, value);
} on RateLimitExceededException {
  // Back off or queue the write
  await Future.delayed(Duration(milliseconds: 100));
  // Retry...
}
```

---

## Choosing a Rate Limiter

| Scenario | Recommended |
|---|---|
| Burst writes, then steady state | `TokenBucket` |
| Strict per-second limit, no burst | `SlidingWindowLimiter` |
| Simple per-minute limit | `FixedWindowLimiter` |
| Per-user / per-entity limits | `PerKeyRateLimiter` |
| Vault-wide multi-operation limits | `VaultRateLimiter` |
