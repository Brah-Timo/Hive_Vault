// lib/src/impl/vault_health.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Health checker for diagnosing vault integrity issues.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';
import '../core/vault_interface.dart';
import '../core/vault_stats.dart';

/// Severity level of a health issue.
enum HealthSeverity { info, warning, error, critical }

/// A single health observation.
@immutable
class HealthIssue {
  final HealthSeverity severity;
  final String code;
  final String message;
  final String? recommendation;

  const HealthIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.recommendation,
  });

  @override
  String toString() => '[${severity.name.toUpperCase()}] $code: $message'
      '${recommendation != null ? '\n  → $recommendation' : ''}';
}

/// Result of a health check run.
@immutable
class HealthReport {
  final DateTime checkedAt;
  final List<HealthIssue> issues;
  final VaultStats stats;

  const HealthReport({
    required this.checkedAt,
    required this.issues,
    required this.stats,
  });

  bool get isHealthy => issues.every((i) => i.severity == HealthSeverity.info);

  bool get hasCritical =>
      issues.any((i) => i.severity == HealthSeverity.critical);

  List<HealthIssue> get errors =>
      issues.where((i) => i.severity == HealthSeverity.error).toList();

  List<HealthIssue> get warnings =>
      issues.where((i) => i.severity == HealthSeverity.warning).toList();

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('═════════════════════════════════════════════')
      ..writeln('  HiveVault Health Report')
      ..writeln('  Checked at: ${checkedAt.toIso8601String()}')
      ..writeln('  Status: ${isHealthy ? "✅ Healthy" : "⚠️ Issues found"}')
      ..writeln('═════════════════════════════════════════════');

    if (issues.isEmpty) {
      buf.writeln('  No issues detected.');
    } else {
      for (final issue in issues) {
        buf.writeln('  $issue');
      }
    }

    buf.writeln('─────────────────────────────────────────────');
    buf.write(stats.toString());
    return buf.toString();
  }
}

/// Runs diagnostic checks against a vault instance.
class VaultHealthChecker {
  // ─── Thresholds ───────────────────────────────────────────────────────────

  /// Cache hit ratio below which a warning is issued (0.0 – 1.0).
  static const double _lowCacheHitRatioThreshold = 0.5;

  /// Entry count above which a warning about index memory usage is issued.
  static const int _largeIndexWarningThreshold = 100000;

  /// Compression ratio below which a warning is issued.
  static const double _lowCompressionRatioThreshold = 0.10;

  /// Runs all health checks and returns a [HealthReport].
  static Future<HealthReport> check(SecureStorageInterface vault) async {
    final stats = await vault.getStats();
    final issues = <HealthIssue>[];

    // ── Cache health ────────────────────────────────────────────────────────
    if (stats.cacheCapacity > 0 && stats.totalReads > 100) {
      if (stats.cacheHitRatio < _lowCacheHitRatioThreshold) {
        issues.add(HealthIssue(
          severity: HealthSeverity.warning,
          code: 'LOW_CACHE_HIT_RATIO',
          message:
              'Cache hit ratio is ${(stats.cacheHitRatio * 100).toStringAsFixed(1)}% '
              '(threshold: ${(_lowCacheHitRatioThreshold * 100).toStringAsFixed(0)}%)',
          recommendation: 'Consider increasing memoryCacheSize in VaultConfig.',
        ));
      } else {
        issues.add(HealthIssue(
          severity: HealthSeverity.info,
          code: 'CACHE_OK',
          message: 'Cache hit ratio is healthy: '
              '${(stats.cacheHitRatio * 100).toStringAsFixed(1)}%',
        ));
      }
    }

    // ── Index health ─────────────────────────────────────────────────────────
    if (stats.indexStats.totalEntries > _largeIndexWarningThreshold) {
      issues.add(HealthIssue(
        severity: HealthSeverity.warning,
        code: 'LARGE_INDEX',
        message: 'Index contains ${stats.indexStats.totalEntries} entries '
            '(memory: ${stats.indexStats.memoryLabel})',
        recommendation:
            'Consider using indexableFields to limit indexed fields.',
      ));
    }

    // ── Compression health ───────────────────────────────────────────────────
    if (stats.totalWrites > 50) {
      final ratio = stats.compressionRatio;
      if (ratio < _lowCompressionRatioThreshold &&
          stats.compressionAlgorithm != 'None') {
        issues.add(HealthIssue(
          severity: HealthSeverity.warning,
          code: 'LOW_COMPRESSION_RATIO',
          message: 'Compression ratio is ${stats.compressionRatioLabel} — '
              'compression may not be beneficial for this data type.',
          recommendation:
              'Consider CompressionStrategy.none or increasing minimumSizeForCompression.',
        ));
      }
    }

    // ── Empty vault ─────────────────────────────────────────────────────────
    if (stats.totalEntries == 0 && stats.totalWrites > 0) {
      issues.add(HealthIssue(
        severity: HealthSeverity.warning,
        code: 'EMPTY_VAULT',
        message: 'Vault appears empty despite recorded writes. '
            'All entries may have been deleted.',
      ));
    }

    // ── Search coverage ──────────────────────────────────────────────────────
    final indexedEntries = stats.indexStats.totalEntries;
    final totalEntries = stats.totalEntries;
    if (totalEntries > 0 && indexedEntries < totalEntries * 0.5) {
      issues.add(HealthIssue(
        severity: HealthSeverity.info,
        code: 'PARTIAL_INDEX',
        message: 'Only $indexedEntries/$totalEntries entries are indexed. '
            'Entries saved without searchableText may not be searchable.',
        recommendation:
            'Call rebuildIndex() or provide searchableText on save.',
      ));
    }

    return HealthReport(
      checkedAt: DateTime.now(),
      issues: issues,
      stats: stats,
    );
  }
}
