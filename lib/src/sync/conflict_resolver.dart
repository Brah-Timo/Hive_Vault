// lib/src/sync/conflict_resolver.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Conflict Resolution Engine.
//
// Provides pluggable conflict resolution strategies when the same key is
// written by two different sources (e.g., offline sync, multi-device, remote
// backup import).
//
// Built-in strategies:
//   • LastWriteWins    — the entry with the newer timestamp wins.
//   • FirstWriteWins   — the entry with the older timestamp is kept.
//   • MergeFields      — field-level merge for Map values.
//   • RemoteWins       — always accept the incoming (remote) value.
//   • LocalWins        — always keep the existing (local) value.
//   • VersionVector    — uses per-key version counters for causal ordering.
//   • Custom           — caller-supplied predicate.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import '../core/vault_exceptions.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Versioned value wrapper
// ═══════════════════════════════════════════════════════════════════════════

/// Wraps any value with metadata needed for conflict resolution.
class VersionedValue<T> {
  /// The actual stored value.
  final T value;

  /// The source identifier (device ID, node ID, user ID, …).
  final String sourceId;

  /// When this version was written.
  final DateTime timestamp;

  /// Logical version counter — incremented on every update to this key.
  final int version;

  /// Vector clock for causal ordering: maps source IDs to their last known
  /// version at the time of this write.
  final Map<String, int> vectorClock;

  /// Arbitrary metadata attached at write time.
  final Map<String, dynamic> metadata;

  const VersionedValue({
    required this.value,
    required this.sourceId,
    required this.timestamp,
    required this.version,
    this.vectorClock = const {},
    this.metadata = const {},
  });

  /// Creates a new [VersionedValue] with an incremented version.
  VersionedValue<T> bump({
    T? newValue,
    required String bySource,
    Map<String, int>? updatedClock,
  }) =>
      VersionedValue(
        value: newValue ?? value,
        sourceId: bySource,
        timestamp: DateTime.now(),
        version: version + 1,
        vectorClock: updatedClock ?? {...vectorClock, bySource: version + 1},
        metadata: metadata,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'sourceId': sourceId,
        'timestamp': timestamp.toIso8601String(),
        'version': version,
        'vectorClock': vectorClock,
        'metadata': metadata,
      };

  @override
  String toString() =>
      'VersionedValue(v$version from $sourceId @ ${timestamp.toIso8601String()})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Conflict description
// ═══════════════════════════════════════════════════════════════════════════

/// Describes a conflict between a local and a remote value for the same key.
class VaultConflict<T> {
  final String key;
  final VersionedValue<T> local;
  final VersionedValue<T> remote;
  final DateTime detectedAt;

  VaultConflict({
    required this.key,
    required this.local,
    required this.remote,
  }) : detectedAt = DateTime.now();

  @override
  String toString() =>
      'VaultConflict(key: $key, local: $local, remote: $remote)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Resolution result
// ═══════════════════════════════════════════════════════════════════════════

/// How a conflict was resolved.
enum ResolutionStrategy {
  localWins,
  remoteWins,
  merged,
  deferred,
}

/// The outcome of resolving a [VaultConflict].
class ConflictResolution<T> {
  final String key;
  final T resolvedValue;
  final ResolutionStrategy strategy;
  final Map<String, dynamic> mergeMetadata;
  final DateTime resolvedAt;

  ConflictResolution({
    required this.key,
    required this.resolvedValue,
    required this.strategy,
    this.mergeMetadata = const {},
  }) : resolvedAt = DateTime.now();

  @override
  String toString() =>
      'ConflictResolution(key: $key, strategy: ${strategy.name})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Abstract resolver interface
// ═══════════════════════════════════════════════════════════════════════════

/// Contract for all conflict resolution strategies.
abstract class ConflictResolver<T> {
  /// Resolves [conflict] and returns the winning value + resolution metadata.
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Built-in resolvers
// ═══════════════════════════════════════════════════════════════════════════

/// Last-write-wins: the entry with the newer [VersionedValue.timestamp] wins.
class LastWriteWinsResolver<T> implements ConflictResolver<T> {
  const LastWriteWinsResolver();

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async {
    final winner = conflict.remote.timestamp.isAfter(conflict.local.timestamp)
        ? conflict.remote
        : conflict.local;
    final strategy = winner == conflict.remote
        ? ResolutionStrategy.remoteWins
        : ResolutionStrategy.localWins;

    return ConflictResolution(
      key: conflict.key,
      resolvedValue: winner.value,
      strategy: strategy,
      mergeMetadata: {
        'winnerTimestamp': winner.timestamp.toIso8601String(),
        'winnerSource': winner.sourceId,
      },
    );
  }
}

/// First-write-wins: the entry with the older timestamp is kept.
class FirstWriteWinsResolver<T> implements ConflictResolver<T> {
  const FirstWriteWinsResolver();

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async {
    final winner = conflict.local.timestamp.isBefore(conflict.remote.timestamp)
        ? conflict.local
        : conflict.remote;
    final strategy = winner == conflict.remote
        ? ResolutionStrategy.remoteWins
        : ResolutionStrategy.localWins;

    return ConflictResolution(
      key: conflict.key,
      resolvedValue: winner.value,
      strategy: strategy,
    );
  }
}

/// Remote always wins — the incoming (remote) value overwrites local.
class RemoteWinsResolver<T> implements ConflictResolver<T> {
  const RemoteWinsResolver();

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async =>
      ConflictResolution(
        key: conflict.key,
        resolvedValue: conflict.remote.value,
        strategy: ResolutionStrategy.remoteWins,
      );
}

/// Local always wins — the existing (local) value is preserved.
class LocalWinsResolver<T> implements ConflictResolver<T> {
  const LocalWinsResolver();

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async =>
      ConflictResolution(
        key: conflict.key,
        resolvedValue: conflict.local.value,
        strategy: ResolutionStrategy.localWins,
      );
}

/// Field-level merge for `Map<String, dynamic>` values.
///
/// Rules:
///   1. Fields present in only one side are kept as-is.
///   2. Scalar conflicts (both sides differ): apply [scalarResolution].
///   3. Nested maps are merged recursively.
///
/// [scalarResolution] defaults to remote-wins for conflicting scalars.
class FieldMergeResolver implements ConflictResolver<Map<String, dynamic>> {
  final ResolutionStrategy scalarResolution;
  final Set<String> localPriorityFields;
  final Set<String> remotePriorityFields;

  const FieldMergeResolver({
    this.scalarResolution = ResolutionStrategy.remoteWins,
    this.localPriorityFields = const {},
    this.remotePriorityFields = const {},
  });

  @override
  Future<ConflictResolution<Map<String, dynamic>>> resolve(
    VaultConflict<Map<String, dynamic>> conflict,
  ) async {
    final merged = _deepMerge(
      conflict.local.value,
      conflict.remote.value,
    );
    return ConflictResolution(
      key: conflict.key,
      resolvedValue: merged,
      strategy: ResolutionStrategy.merged,
      mergeMetadata: {
        'localVersion': conflict.local.version,
        'remoteVersion': conflict.remote.version,
        'mergedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final result = Map<String, dynamic>.from(local);
    for (final entry in remote.entries) {
      final key = entry.key;
      final remoteVal = entry.value;
      final localVal = local[key];

      if (!local.containsKey(key)) {
        // Remote-only field → include.
        result[key] = remoteVal;
      } else if (localPriorityFields.contains(key)) {
        result[key] = localVal;
      } else if (remotePriorityFields.contains(key)) {
        result[key] = remoteVal;
      } else if (remoteVal is Map<String, dynamic> &&
          localVal is Map<String, dynamic>) {
        // Recurse for nested maps.
        result[key] = _deepMerge(localVal, remoteVal);
      } else if (remoteVal != localVal) {
        // Scalar conflict: apply configured resolution.
        result[key] = scalarResolution == ResolutionStrategy.localWins
            ? localVal
            : remoteVal;
      }
      // else values are equal → no change needed.
    }
    return result;
  }
}

/// Version-vector resolver: uses causal ordering to pick the causally
/// greater version.  If concurrent (neither dominates), falls back to LWW.
class VersionVectorResolver<T> implements ConflictResolver<T> {
  final ConflictResolver<T> _fallback;

  VersionVectorResolver({ConflictResolver<T>? fallback})
      : _fallback = fallback ?? LastWriteWinsResolver<T>();

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async {
    final localDominates = _dominates(
      conflict.local.vectorClock,
      conflict.remote.vectorClock,
    );
    final remoteDominates = _dominates(
      conflict.remote.vectorClock,
      conflict.local.vectorClock,
    );

    if (localDominates && !remoteDominates) {
      return ConflictResolution(
        key: conflict.key,
        resolvedValue: conflict.local.value,
        strategy: ResolutionStrategy.localWins,
        mergeMetadata: {'reason': 'local vector dominates'},
      );
    }
    if (remoteDominates && !localDominates) {
      return ConflictResolution(
        key: conflict.key,
        resolvedValue: conflict.remote.value,
        strategy: ResolutionStrategy.remoteWins,
        mergeMetadata: {'reason': 'remote vector dominates'},
      );
    }
    // Concurrent → fall back.
    return _fallback.resolve(conflict);
  }

  /// Returns `true` if [a] causally dominates [b]:
  /// ∀ key in b: a[key] ≥ b[key], and ∃ key: a[key] > b[key].
  bool _dominates(Map<String, int> a, Map<String, int> b) {
    bool hasHigher = false;
    for (final entry in b.entries) {
      final aVal = a[entry.key] ?? 0;
      if (aVal < entry.value) return false;
      if (aVal > entry.value) hasHigher = true;
    }
    // Also consider keys only in a.
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) && entry.value > 0) hasHigher = true;
    }
    return hasHigher;
  }
}

/// Defers resolution: adds the conflict to a queue for manual handling.
class DeferredResolver<T> implements ConflictResolver<T> {
  final List<VaultConflict<T>> _queue = [];

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) async {
    _queue.add(conflict);
    return ConflictResolution(
      key: conflict.key,
      resolvedValue: conflict.local.value, // Keep local until resolved.
      strategy: ResolutionStrategy.deferred,
    );
  }

  /// Returns all pending conflicts.
  List<VaultConflict<T>> get pendingConflicts => List.unmodifiable(_queue);

  /// Manually resolves a deferred conflict with [resolvedValue].
  void resolveManually(String key, T resolvedValue) {
    _queue.removeWhere((c) => c.key == key);
  }

  /// Clears all deferred conflicts.
  void clearAll() => _queue.clear();
}

/// Custom resolver that delegates to a user-supplied callback.
class CustomResolver<T> implements ConflictResolver<T> {
  final Future<ConflictResolution<T>> Function(VaultConflict<T>) _handler;

  CustomResolver(this._handler);

  @override
  Future<ConflictResolution<T>> resolve(VaultConflict<T> conflict) =>
      _handler(conflict);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Conflict detection helper
// ═══════════════════════════════════════════════════════════════════════════

/// Detects conflicts in a batch of [incoming] entries against the [existing]
/// map of locally-stored versioned values.
class ConflictDetector<T> {
  /// Returns a list of [VaultConflict] for any key where both sides differ.
  static List<VaultConflict<T>> detect<T>({
    required Map<String, VersionedValue<T>> existing,
    required Map<String, VersionedValue<T>> incoming,
  }) {
    final conflicts = <VaultConflict<T>>[];
    for (final entry in incoming.entries) {
      final key = entry.key;
      final remote = entry.value;
      final local = existing[key];

      if (local == null) continue; // No conflict — new key.
      if (local.value == remote.value) continue; // Same value — no conflict.

      conflicts.add(VaultConflict(key: key, local: local, remote: remote));
    }
    return conflicts;
  }
}
