// lib/src/cache/rate_limiter.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Token-Bucket Rate Limiter.
//
// Prevents runaway write/read/search bursts that could overwhelm the vault or
// consume excessive battery on mobile devices.
//
// Supports per-operation and per-key rate limiting using the token-bucket
// algorithm, which allows short bursts while enforcing an average rate.
//
// Algorithms:
//   • TokenBucket  — fill at [refillRate] tokens/sec, burst up to [capacity].
//   • SlidingWindow — rolling window counter (alternative, no burst allowance).
//   • FixedWindow   — simple per-second/minute counter with hard reset.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import '../core/vault_exceptions.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Token Bucket
// ═══════════════════════════════════════════════════════════════════════════

/// A single token-bucket rate limiter.
///
/// Tokens refill continuously at [refillRate] per second, up to [capacity].
/// An operation costs [cost] tokens (default 1). If insufficient tokens are
/// available the bucket is either:
///   • [RateLimitBehavior.reject]  — throws [RateLimitExceededException].
///   • [RateLimitBehavior.wait]    — waits until enough tokens refill.
///   • [RateLimitBehavior.throttle]— drops silently (returns false).
class TokenBucket {
  /// Maximum tokens the bucket can hold (burst capacity).
  final double capacity;

  /// Rate at which tokens refill per second.
  final double refillRate;

  double _tokens;
  DateTime _lastRefill;

  TokenBucket({
    required this.capacity,
    required this.refillRate,
  })  : _tokens = capacity,
        _lastRefill = DateTime.now();

  // ── State ─────────────────────────────────────────────────────────────────

  /// Current token count (after virtual refill).
  double get availableTokens {
    _refill();
    return _tokens;
  }

  /// Remaining capacity before the bucket is full (float).
  double get remainingCapacity => capacity - availableTokens;

  // ── Consume ───────────────────────────────────────────────────────────────

  /// Attempts to consume [cost] tokens.
  ///
  /// Returns `true` if successful, `false` if insufficient tokens available.
  bool tryConsume({double cost = 1.0}) {
    _refill();
    if (_tokens >= cost) {
      _tokens -= cost;
      return true;
    }
    return false;
  }

  /// Consumes [cost] tokens or throws [RateLimitExceededException].
  void consume({double cost = 1.0}) {
    if (!tryConsume(cost: cost)) {
      throw RateLimitExceededException(
        'Rate limit exceeded: need $cost tokens, have '
        '${_tokens.toStringAsFixed(2)} (capacity: $capacity, '
        'refill: ${refillRate}/s)',
      );
    }
  }

  /// Waits until [cost] tokens become available, then consumes them.
  Future<void> consumeAsync({double cost = 1.0}) async {
    while (!tryConsume(cost: cost)) {
      // Wait for enough tokens to refill: (cost - _tokens) / refillRate seconds.
      final waitSeconds = (cost - _tokens) / refillRate;
      await Future.delayed(
        Duration(milliseconds: (waitSeconds * 1000).ceil()),
      );
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Fills the bucket to full capacity immediately.
  void refillFull() {
    _tokens = capacity;
    _lastRefill = DateTime.now();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    final newTokens = elapsed * refillRate;
    _tokens = (_tokens + newTokens).clamp(0.0, capacity);
    _lastRefill = now;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sliding Window Counter
// ═══════════════════════════════════════════════════════════════════════════

/// Sliding-window rate limiter: no burst allowance, pure rolling-window count.
class SlidingWindowLimiter {
  final int maxRequests;
  final Duration window;
  final List<DateTime> _timestamps = [];

  SlidingWindowLimiter({
    required this.maxRequests,
    required this.window,
  });

  /// Returns `true` if the request is allowed (and records it).
  bool tryAcquire() {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
    if (_timestamps.length < maxRequests) {
      _timestamps.add(now);
      return true;
    }
    return false;
  }

  void acquire() {
    if (!tryAcquire()) {
      throw RateLimitExceededException(
        'Sliding window rate limit: max $maxRequests requests per '
        '${window.inSeconds}s exceeded',
      );
    }
  }

  int get currentCount {
    final cutoff = DateTime.now().subtract(window);
    return _timestamps.where((t) => t.isAfter(cutoff)).length;
  }

  double get utilizationRatio => currentCount / maxRequests;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Fixed Window Counter
// ═══════════════════════════════════════════════════════════════════════════

/// Fixed-window rate limiter: resets counter every [window] duration.
class FixedWindowLimiter {
  final int maxRequests;
  final Duration window;

  int _count = 0;
  DateTime _windowStart = DateTime.now();

  FixedWindowLimiter({required this.maxRequests, required this.window});

  bool tryAcquire() {
    final now = DateTime.now();
    if (now.difference(_windowStart) >= window) {
      _count = 0;
      _windowStart = now;
    }
    if (_count < maxRequests) {
      _count++;
      return true;
    }
    return false;
  }

  void acquire() {
    if (!tryAcquire()) {
      throw RateLimitExceededException(
        'Fixed window rate limit: max $maxRequests per '
        '${window.inSeconds}s exceeded (reset in '
        '${(window - DateTime.now().difference(_windowStart)).inMilliseconds}ms)',
      );
    }
  }

  int get remaining {
    if (DateTime.now().difference(_windowStart) >= window) return maxRequests;
    return maxRequests - _count;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Per-key rate limiter
// ═══════════════════════════════════════════════════════════════════════════

/// Maintains per-key token buckets, useful for per-entity throttling.
///
/// Evicts inactive buckets after [bucketTtl] to prevent unbounded growth.
class PerKeyRateLimiter {
  final double capacity;
  final double refillRate;
  final Duration bucketTtl;
  final int maxBuckets;

  final Map<String, _BucketEntry> _buckets = {};

  PerKeyRateLimiter({
    required this.capacity,
    required this.refillRate,
    this.bucketTtl = const Duration(minutes: 10),
    this.maxBuckets = 10000,
  });

  bool tryConsume(String key, {double cost = 1.0}) {
    _evictStale();
    final entry = _buckets.putIfAbsent(
      key,
      () =>
          _BucketEntry(TokenBucket(capacity: capacity, refillRate: refillRate)),
    );
    entry.lastAccess = DateTime.now();
    return entry.bucket.tryConsume(cost: cost);
  }

  void consume(String key, {double cost = 1.0}) {
    if (!tryConsume(key, cost: cost)) {
      throw RateLimitExceededException(
        'Per-key rate limit exceeded for "$key"',
      );
    }
  }

  int get activeBuckets => _buckets.length;

  void _evictStale() {
    if (_buckets.length < maxBuckets) return;
    final cutoff = DateTime.now().subtract(bucketTtl);
    _buckets.removeWhere((_, entry) => entry.lastAccess.isBefore(cutoff));
  }
}

class _BucketEntry {
  final TokenBucket bucket;
  DateTime lastAccess;
  _BucketEntry(this.bucket) : lastAccess = DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════
//  VaultRateLimiter — composite limiter for vault operations
// ═══════════════════════════════════════════════════════════════════════════

/// Combines per-operation buckets so that writes, reads, and searches
/// have independent rate limits.
class VaultRateLimiter {
  final TokenBucket? writeLimit;
  final TokenBucket? readLimit;
  final TokenBucket? searchLimit;
  final TokenBucket? deleteLimit;

  final List<String> _violations = [];

  VaultRateLimiter({
    this.writeLimit,
    this.readLimit,
    this.searchLimit,
    this.deleteLimit,
  });

  /// Standard profile: 1000 writes/sec, 5000 reads/sec, 100 searches/sec.
  factory VaultRateLimiter.standard() => VaultRateLimiter(
        writeLimit: TokenBucket(capacity: 1000, refillRate: 1000),
        readLimit: TokenBucket(capacity: 5000, refillRate: 5000),
        searchLimit: TokenBucket(capacity: 100, refillRate: 100),
        deleteLimit: TokenBucket(capacity: 500, refillRate: 500),
      );

  /// Conservative mobile profile for battery-constrained devices.
  factory VaultRateLimiter.mobile() => VaultRateLimiter(
        writeLimit: TokenBucket(capacity: 100, refillRate: 50),
        readLimit: TokenBucket(capacity: 500, refillRate: 200),
        searchLimit: TokenBucket(capacity: 20, refillRate: 10),
        deleteLimit: TokenBucket(capacity: 100, refillRate: 50),
      );

  void checkWrite() {
    if (writeLimit != null && !writeLimit!.tryConsume()) {
      _recordViolation('write');
      throw RateLimitExceededException('Write rate limit exceeded');
    }
  }

  void checkRead() {
    if (readLimit != null && !readLimit!.tryConsume()) {
      _recordViolation('read');
      throw RateLimitExceededException('Read rate limit exceeded');
    }
  }

  void checkSearch() {
    if (searchLimit != null && !searchLimit!.tryConsume()) {
      _recordViolation('search');
      throw RateLimitExceededException('Search rate limit exceeded');
    }
  }

  void checkDelete() {
    if (deleteLimit != null && !deleteLimit!.tryConsume()) {
      _recordViolation('delete');
      throw RateLimitExceededException('Delete rate limit exceeded');
    }
  }

  List<String> get violations => List.unmodifiable(_violations);
  int get violationCount => _violations.length;

  void _recordViolation(String op) {
    _violations.add('$op @ ${DateTime.now().toIso8601String()}');
    if (_violations.length > 500) _violations.removeAt(0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Exception
// ═══════════════════════════════════════════════════════════════════════════

/// Thrown when a rate limit is exceeded and [RateLimitBehavior.reject] is set.
class RateLimitExceededException extends VaultException {
  const RateLimitExceededException(super.message, {super.cause});

  @override
  String toString() => 'RateLimitExceededException: $message';
}
