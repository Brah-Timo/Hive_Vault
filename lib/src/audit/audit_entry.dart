// lib/src/audit/audit_entry.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — A single immutable audit log entry.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';

/// The action category recorded in an [AuditEntry].
enum AuditAction {
  save,
  get,
  delete,
  search,
  batchSave,
  batchGet,
  batchDelete,
  rebuildIndex,
  compact,
  exportData,
  importData,
  keyRotation,
  cacheHit,
  cacheMiss,
  error,
}

/// An immutable record of a single vault operation.
@immutable
class AuditEntry {
  /// When the operation occurred.
  final DateTime timestamp;

  /// Action category.
  final AuditAction action;

  /// The primary storage key involved (if applicable).
  final String key;

  /// Original data size before compression (bytes). May be `null`.
  final int? originalSize;

  /// Data size after compression (bytes). May be `null`.
  final int? compressedSize;

  /// Data size after encryption (bytes). May be `null`.
  final int? encryptedSize;

  /// Whether the data was served from the LRU cache.
  final bool fromCache;

  /// How long the operation took (wall-clock).
  final Duration? elapsed;

  /// Optional free-text detail or error message.
  final String? details;

  const AuditEntry({
    required this.timestamp,
    required this.action,
    required this.key,
    this.originalSize,
    this.compressedSize,
    this.encryptedSize,
    this.fromCache = false,
    this.elapsed,
    this.details,
  });

  // ─── Computed helpers ─────────────────────────────────────────────────────

  /// Compression ratio (0.0 = no saving, 0.8 = 80% smaller).
  double? get compressionRatio {
    if (originalSize == null || compressedSize == null || originalSize == 0) {
      return null;
    }
    return 1.0 - (compressedSize! / originalSize!);
  }

  String get compressionRatioLabel {
    final r = compressionRatio;
    if (r == null) return 'N/A';
    return '${(r * 100).toStringAsFixed(1)}%';
  }

  String get elapsedLabel {
    if (elapsed == null) return 'N/A';
    final ms = elapsed!.inMicroseconds / 1000.0;
    return '${ms.toStringAsFixed(2)} ms';
  }

  // ─── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'action': action.name,
        'key': key,
        if (originalSize != null) 'originalSize': originalSize,
        if (compressedSize != null) 'compressedSize': compressedSize,
        if (encryptedSize != null) 'encryptedSize': encryptedSize,
        'fromCache': fromCache,
        if (elapsed != null) 'elapsedUs': elapsed!.inMicroseconds,
        if (details != null) 'details': details,
      };

  @override
  String toString() {
    final buf = StringBuffer('[${timestamp.toIso8601String()}] '
        '${action.name.toUpperCase()} key="$key"');
    if (originalSize != null) {
      buf.write(' size=${originalSize}B→${compressedSize ?? "?"}B'
          ' (compressed $compressionRatioLabel)');
    }
    if (fromCache) buf.write(' [CACHE]');
    if (elapsed != null) buf.write(' [$elapsedLabel]');
    if (details != null) buf.write(' | $details');
    return buf.toString();
  }
}
