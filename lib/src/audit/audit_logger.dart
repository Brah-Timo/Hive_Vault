// lib/src/audit/audit_logger.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Audit logger: records every significant vault operation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'audit_entry.dart';

/// Records vault operations in a bounded in-memory ring buffer and
/// provides filtering, export, and summary capabilities.
///
/// The audit log is write-only during normal vault operation; it does NOT
/// affect vault performance. Log entries are emitted in addition to the
/// normal operation — they are never used as part of the data pipeline.
///
/// ## Capacity
/// The log keeps at most [maxEntries] entries. When full the oldest entry
/// is removed to make room for the new one (FIFO ring-buffer behaviour).
class AuditLogger {
  /// Maximum number of entries retained in memory.
  final int maxEntries;

  final List<AuditEntry> _log = [];

  AuditLogger({this.maxEntries = 1000}) : assert(maxEntries > 0);

  // ─── Write ────────────────────────────────────────────────────────────────

  /// Records a new audit entry. If the log is full the oldest entry is dropped.
  void record(AuditEntry entry) {
    if (_log.length >= maxEntries) _log.removeAt(0);
    _log.add(entry);
  }

  /// Convenience method to create and record an entry in one call.
  void log({
    required AuditAction action,
    required String key,
    int? originalSize,
    int? compressedSize,
    int? encryptedSize,
    bool fromCache = false,
    Duration? elapsed,
    String? details,
  }) {
    record(AuditEntry(
      timestamp: DateTime.now(),
      action: action,
      key: key,
      originalSize: originalSize,
      compressedSize: compressedSize,
      encryptedSize: encryptedSize,
      fromCache: fromCache,
      elapsed: elapsed,
      details: details,
    ));
  }

  // ─── Read / Query ─────────────────────────────────────────────────────────

  /// Total number of entries in the log.
  int get length => _log.length;

  /// Returns `true` if no entries have been recorded yet.
  bool get isEmpty => _log.isEmpty;

  /// Returns the [count] most recent entries (newest first).
  List<AuditEntry> getRecent({int count = 50}) {
    final effective = count.clamp(1, _log.length);
    return _log.reversed.take(effective).toList(growable: false);
  }

  /// Returns all entries for a specific storage [key].
  List<AuditEntry> getByKey(String key) =>
      _log.where((e) => e.key == key).toList(growable: false);

  /// Returns all entries with the given [action].
  List<AuditEntry> getByAction(AuditAction action) =>
      _log.where((e) => e.action == action).toList(growable: false);

  /// Returns entries whose timestamp falls within [start]..[end].
  List<AuditEntry> getByTimeRange(DateTime start, DateTime end) => _log
      .where((e) =>
          e.timestamp.isAfter(start) && e.timestamp.isBefore(end))
      .toList(growable: false);

  /// Returns entries that recorded errors (action == [AuditAction.error]).
  List<AuditEntry> getErrors() => getByAction(AuditAction.error);

  // ─── Statistics ───────────────────────────────────────────────────────────

  /// Returns a summary map with per-action counts and totals.
  Map<String, dynamic> getSummary() {
    final counts = <String, int>{};
    int totalBytesOriginal = 0;
    int totalBytesCompressed = 0;
    int cacheHits = 0;
    int cacheMisses = 0;
    Duration totalElapsed = Duration.zero;

    for (final entry in _log) {
      counts[entry.action.name] = (counts[entry.action.name] ?? 0) + 1;
      totalBytesOriginal += entry.originalSize ?? 0;
      totalBytesCompressed += entry.compressedSize ?? 0;
      if (entry.fromCache) cacheHits++; else cacheMisses++;
      if (entry.elapsed != null) totalElapsed += entry.elapsed!;
    }

    final totalEntries = _log.length;
    final compressionRatio = totalBytesOriginal == 0
        ? 0.0
        : 1.0 - (totalBytesCompressed / totalBytesOriginal);

    return {
      'totalEntries': totalEntries,
      'actionCounts': counts,
      'totalOriginalBytes': totalBytesOriginal,
      'totalCompressedBytes': totalBytesCompressed,
      'compressionRatio': double.parse(compressionRatio.toStringAsFixed(4)),
      'cacheHits': cacheHits,
      'cacheMisses': cacheMisses,
      'cacheHitRatio': totalEntries == 0
          ? 0.0
          : double.parse((cacheHits / totalEntries).toStringAsFixed(4)),
      'totalElapsedMs': totalElapsed.inMilliseconds,
    };
  }

  // ─── Export ───────────────────────────────────────────────────────────────

  /// Exports all log entries as a UTF-8 JSON byte array.
  Uint8List exportJson() {
    final list = _log.map((e) => e.toMap()).toList();
    return Uint8List.fromList(utf8.encode(jsonEncode(list)));
  }

  /// Returns a formatted plain-text report of recent entries.
  String formatReport({int count = 20}) {
    final entries = getRecent(count: count);
    if (entries.isEmpty) return 'Audit log is empty.';

    final buf = StringBuffer()
      ..writeln('═══════════════════════════════════════════════')
      ..writeln('  HiveVault Audit Log  (${entries.length} entries shown)')
      ..writeln('═══════════════════════════════════════════════');
    for (final e in entries) {
      buf.writeln(e.toString());
    }
    buf.writeln('───────────────────────────────────────────────');

    final summary = getSummary();
    buf
      ..writeln('Total entries : ${summary['totalEntries']}')
      ..writeln('Cache hit ratio: '
          '${((summary['cacheHitRatio'] as double) * 100).toStringAsFixed(1)}%')
      ..writeln('Avg compression: '
          '${((summary['compressionRatio'] as double) * 100).toStringAsFixed(1)}%')
      ..writeln('═══════════════════════════════════════════════');

    return buf.toString();
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Removes all entries from the log.
  void clear() => _log.clear();

  @override
  String toString() => 'AuditLogger(${_log.length}/$maxEntries entries)';
}
