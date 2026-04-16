// lib/src/impl/ttl_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — TTL (Time-To-Live) support for auto-expiring entries.
// ─────────────────────────────────────────────────────────────────────────────
//
// TTL metadata is stored in a dedicated Hive box alongside the data box.
// Expired entries are lazily evicted on read and actively purged during
// periodic cleanup sweeps.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:hive/hive.dart';

/// Manages TTL (time-to-live) metadata for HiveVault entries.
///
/// Usage:
/// ```dart
/// final ttl = TtlManager(dataBoxName: 'sessions');
/// await ttl.initialize();
///
/// // Save with TTL
/// await ttl.setExpiry('TOKEN-123', Duration(hours: 24));
///
/// // Check if expired
/// if (await ttl.isExpired('TOKEN-123')) {
///   await vault.secureDelete('TOKEN-123');
/// }
/// ```
class TtlManager {
  final String dataBoxName;
  Box<int>? _ttlBox;
  Timer? _purgeTimer;

  TtlManager({required this.dataBoxName});

  String get _ttlBoxName => '__ttl_${dataBoxName}__';

  /// Opens the TTL metadata box.
  Future<void> initialize() async {
    _ttlBox = await Hive.openBox<int>(_ttlBoxName);
  }

  /// Sets an expiry for [key].
  ///
  /// [duration] is measured from now. Use [Duration.zero] to remove TTL.
  Future<void> setExpiry(String key, Duration duration) async {
    _requireInit();
    if (duration == Duration.zero) {
      await _ttlBox!.delete(key);
      return;
    }
    final expireAt = DateTime.now().add(duration).millisecondsSinceEpoch;
    await _ttlBox!.put(key, expireAt);
  }

  /// Returns `true` if [key] has an expiry that has already passed.
  bool isExpired(String key) {
    _requireInit();
    final expireAt = _ttlBox!.get(key);
    if (expireAt == null) return false; // No TTL set → never expires.
    return DateTime.now().millisecondsSinceEpoch > expireAt;
  }

  /// Returns the [DateTime] at which [key] expires, or `null` if no TTL.
  DateTime? getExpiry(String key) {
    _requireInit();
    final ms = _ttlBox!.get(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Returns remaining TTL for [key], or `null` if no TTL or already expired.
  Duration? getRemaining(String key) {
    final expiry = getExpiry(key);
    if (expiry == null) return null;
    final remaining = expiry.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Removes the TTL record for [key].
  Future<void> clearExpiry(String key) async {
    _requireInit();
    await _ttlBox!.delete(key);
  }

  /// Returns all keys that have expired (lazy evaluation).
  Iterable<String> expiredKeys() {
    _requireInit();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _ttlBox!.keys
        .cast<String>()
        .where((k) => (_ttlBox!.get(k) ?? 0) < now);
  }

  /// Returns all keys that have an active (non-expired) TTL.
  Iterable<String> activeKeys() {
    _requireInit();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _ttlBox!.keys
        .cast<String>()
        .where((k) => (_ttlBox!.get(k) ?? 0) >= now);
  }

  /// Starts a periodic purge sweep every [interval].
  ///
  /// [onExpired] is called for each expired key so the caller can delete
  /// the actual vault entry.
  void startAutoPurge({
    Duration interval = const Duration(minutes: 5),
    required Future<void> Function(String key) onExpired,
  }) {
    _purgeTimer?.cancel();
    _purgeTimer = Timer.periodic(interval, (_) async {
      final expired = expiredKeys().toList();
      for (final key in expired) {
        try {
          await onExpired(key);
          await clearExpiry(key);
        } catch (_) {
          // Don't let one failure stop the rest.
        }
      }
    });
  }

  /// Stops the auto-purge timer.
  void stopAutoPurge() => _purgeTimer?.cancel();

  /// Runs a single manual purge sweep.
  Future<List<String>> purgeNow({
    required Future<void> Function(String key) onExpired,
  }) async {
    final expired = expiredKeys().toList();
    for (final key in expired) {
      try {
        await onExpired(key);
        await clearExpiry(key);
      } catch (_) {}
    }
    return expired;
  }

  Future<void> close() async {
    stopAutoPurge();
    await _ttlBox?.close();
  }

  void _requireInit() {
    assert(_ttlBox != null, 'TtlManager not initialised. Call initialize() first.');
  }
}
