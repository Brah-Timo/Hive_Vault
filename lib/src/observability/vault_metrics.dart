// lib/src/observability/vault_metrics.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Observability & Metrics Collector.
//
// Provides a structured telemetry layer for production monitoring:
//   • Operation counters (reads, writes, deletes, searches, errors).
//   • Latency histograms with configurable buckets (p50, p95, p99).
//   • Throughput tracking (ops/sec, bytes/sec).
//   • Error rate calculation.
//   • Prometheus-style text export.
//   • JSON export for custom dashboards.
//   • Period snapshots with delta computation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
//  Operation type enum
// ═══════════════════════════════════════════════════════════════════════════

enum MetricOperation { read, write, delete, search, batchRead, batchWrite, batchDelete, export, import }

// ═══════════════════════════════════════════════════════════════════════════
//  Histogram
// ═══════════════════════════════════════════════════════════════════════════

/// A fixed-bucket latency histogram for O(1) recording and percentile queries.
class LatencyHistogram {
  // Bucket upper bounds in microseconds.
  static const List<int> _bucketBounds = [
    100,    // 0.1 ms
    500,    // 0.5 ms
    1000,   // 1 ms
    5000,   // 5 ms
    10000,  // 10 ms
    25000,  // 25 ms
    50000,  // 50 ms
    100000, // 100 ms
    250000, // 250 ms
    500000, // 500 ms
  ];

  final List<int> _counts;
  int _overflowCount = 0; // > last bucket
  int _totalCount = 0;
  int _sumUs = 0;
  int _minUs = 0;
  int _maxUs = 0;
  bool _hasData = false;

  LatencyHistogram() : _counts = List.filled(_bucketBounds.length, 0);

  /// Records a single observation of [microseconds].
  void record(int microseconds) {
    if (!_hasData) {
      _minUs = microseconds;
      _maxUs = microseconds;
      _hasData = true;
    } else {
      if (microseconds < _minUs) _minUs = microseconds;
      if (microseconds > _maxUs) _maxUs = microseconds;
    }
    _sumUs += microseconds;
    _totalCount++;

    bool placed = false;
    for (int i = 0; i < _bucketBounds.length; i++) {
      if (microseconds <= _bucketBounds[i]) {
        _counts[i]++;
        placed = true;
        break;
      }
    }
    if (!placed) _overflowCount++;
  }

  int get count => _totalCount;
  double get meanUs => _totalCount == 0 ? 0.0 : _sumUs / _totalCount;
  int get minUs => _hasData ? _minUs : 0;
  int get maxUs => _hasData ? _maxUs : 0;

  /// Returns the approximate [percentile] (0–100) in microseconds.
  int percentile(double p) {
    if (_totalCount == 0) return 0;
    final target = (_totalCount * p / 100.0).ceil();
    int cumulative = 0;
    for (int i = 0; i < _bucketBounds.length; i++) {
      cumulative += _counts[i];
      if (cumulative >= target) return _bucketBounds[i];
    }
    return _maxUs;
  }

  int get p50 => percentile(50);
  int get p95 => percentile(95);
  int get p99 => percentile(99);

  void reset() {
    for (int i = 0; i < _counts.length; i++) _counts[i] = 0;
    _overflowCount = 0;
    _totalCount = 0;
    _sumUs = 0;
    _minUs = 0;
    _maxUs = 0;
    _hasData = false;
  }

  Map<String, dynamic> toJson() => {
        'count': _totalCount,
        'meanUs': meanUs.round(),
        'minUs': minUs,
        'maxUs': maxUs,
        'p50Us': p50,
        'p95Us': p95,
        'p99Us': p99,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
//  Counter
// ═══════════════════════════════════════════════════════════════════════════

/// A simple monotonic counter with optional rate computation.
class MetricCounter {
  int _value = 0;
  final DateTime _createdAt = DateTime.now();

  void increment([int by = 1]) => _value += by;
  int get value => _value;
  void reset() => _value = 0;

  /// Returns average rate (events per second) since creation.
  double get ratePerSecond {
    final secs = DateTime.now().difference(_createdAt).inSeconds;
    return secs == 0 ? 0.0 : _value / secs;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Snapshot
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable snapshot of all metrics at a point in time.
class MetricsSnapshot {
  final DateTime capturedAt;
  final Map<String, int> counters;
  final Map<String, Map<String, dynamic>> histograms;
  final double errorRate;
  final int uptimeSeconds;
  final Map<String, double> throughput; // ops/sec per operation

  const MetricsSnapshot({
    required this.capturedAt,
    required this.counters,
    required this.histograms,
    required this.errorRate,
    required this.uptimeSeconds,
    required this.throughput,
  });

  /// Computes a delta snapshot showing the difference since [previous].
  MetricsSnapshot delta(MetricsSnapshot previous) {
    final deltaCounters = <String, int>{};
    for (final key in counters.keys) {
      deltaCounters[key] =
          (counters[key] ?? 0) - (previous.counters[key] ?? 0);
    }
    return MetricsSnapshot(
      capturedAt: capturedAt,
      counters: deltaCounters,
      histograms: histograms,
      errorRate: errorRate,
      uptimeSeconds: uptimeSeconds - previous.uptimeSeconds,
      throughput: throughput,
    );
  }

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        'counters': counters,
        'histograms': histograms,
        'errorRate': double.parse(errorRate.toStringAsFixed(4)),
        'uptimeSeconds': uptimeSeconds,
        'throughput': {
          for (final e in throughput.entries)
            e.key: double.parse(e.value.toStringAsFixed(2)),
        },
      };

  @override
  String toString() => toJson().toString();
}

// ═══════════════════════════════════════════════════════════════════════════
//  VaultMetrics — main collector
// ═══════════════════════════════════════════════════════════════════════════

/// Collects and exposes structured metrics for a vault instance.
///
/// Usage:
/// ```dart
/// final metrics = VaultMetrics(vaultName: 'users');
/// metrics.recordOperation(MetricOperation.write, durationUs: 1250, bytes: 512);
/// final snapshot = metrics.snapshot();
/// print(metrics.toPrometheusText());
/// ```
class VaultMetrics {
  final String vaultName;
  final DateTime _startedAt;

  // ── Counters ──────────────────────────────────────────────────────────────
  final Map<MetricOperation, MetricCounter> _opCounters = {
    for (final op in MetricOperation.values) op: MetricCounter(),
  };
  final MetricCounter _errorCounter = MetricCounter();
  final MetricCounter _cacheHitCounter = MetricCounter();
  final MetricCounter _cacheMissCounter = MetricCounter();
  final MetricCounter _totalBytesRead = MetricCounter();
  final MetricCounter _totalBytesWritten = MetricCounter();

  // ── Histograms ────────────────────────────────────────────────────────────
  final Map<MetricOperation, LatencyHistogram> _histograms = {
    for (final op in MetricOperation.values) op: LatencyHistogram(),
  };

  // ── Periodic snapshot stream ──────────────────────────────────────────────
  final StreamController<MetricsSnapshot> _snapshotStream =
      StreamController.broadcast();
  Timer? _periodicTimer;
  MetricsSnapshot? _lastSnapshot;

  Stream<MetricsSnapshot> get snapshots => _snapshotStream.stream;

  VaultMetrics({required this.vaultName}) : _startedAt = DateTime.now();

  // ── Recording ─────────────────────────────────────────────────────────────

  /// Records a completed operation.
  ///
  /// [durationUs] is the wall-clock duration in microseconds.
  /// [bytes]      is the number of bytes read/written (optional).
  /// [fromCache]  indicates a cache hit for read operations.
  /// [isError]    marks this record as an error.
  void recordOperation(
    MetricOperation op, {
    required int durationUs,
    int bytes = 0,
    bool fromCache = false,
    bool isError = false,
  }) {
    _opCounters[op]!.increment();
    _histograms[op]!.record(durationUs);

    if (isError) _errorCounter.increment();

    if (op == MetricOperation.read || op == MetricOperation.batchRead) {
      _totalBytesRead.increment(bytes);
      if (fromCache) _cacheHitCounter.increment();
      else _cacheMissCounter.increment();
    }
    if (op == MetricOperation.write || op == MetricOperation.batchWrite) {
      _totalBytesWritten.increment(bytes);
    }
  }

  // ── Snapshot ──────────────────────────────────────────────────────────────

  /// Captures the current metric state as an immutable [MetricsSnapshot].
  MetricsSnapshot snapshot() {
    final totalOps = _opCounters.values.fold(0, (s, c) => s + c.value);
    final errors = _errorCounter.value;
    final errorRate = totalOps == 0 ? 0.0 : errors / totalOps;
    final uptime = DateTime.now().difference(_startedAt).inSeconds;

    return MetricsSnapshot(
      capturedAt: DateTime.now(),
      counters: {
        for (final e in _opCounters.entries)
          e.key.name: e.value.value,
        'errors': errors,
        'cacheHits': _cacheHitCounter.value,
        'cacheMisses': _cacheMissCounter.value,
        'totalBytesRead': _totalBytesRead.value,
        'totalBytesWritten': _totalBytesWritten.value,
      },
      histograms: {
        for (final e in _histograms.entries)
          if (e.value.count > 0) e.key.name: e.value.toJson(),
      },
      errorRate: errorRate,
      uptimeSeconds: uptime,
      throughput: {
        for (final e in _opCounters.entries)
          if (uptime > 0) e.key.name: e.value.value / uptime,
      },
    );
  }

  // ── Periodic snapshots ────────────────────────────────────────────────────

  /// Starts emitting snapshots every [interval] on [snapshots] stream.
  void startPeriodicSnapshots({Duration interval = const Duration(seconds: 60)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      final snap = snapshot();
      _lastSnapshot = snap;
      if (!_snapshotStream.isClosed) _snapshotStream.add(snap);
    });
  }

  void stopPeriodicSnapshots() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  // ── Export formats ────────────────────────────────────────────────────────

  /// Exports metrics in Prometheus text format.
  String toPrometheusText() {
    final snap = snapshot();
    final buf = StringBuffer();
    final prefix = 'hive_vault_${vaultName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

    buf.writeln('# HELP ${prefix}_operations_total Total operations by type');
    buf.writeln('# TYPE ${prefix}_operations_total counter');
    for (final e in snap.counters.entries) {
      buf.writeln('${prefix}_operations_total{operation="${e.key}"} ${e.value}');
    }

    buf.writeln('# HELP ${prefix}_latency_microseconds Operation latency');
    buf.writeln('# TYPE ${prefix}_latency_microseconds summary');
    for (final e in snap.histograms.entries) {
      final h = e.value;
      buf.writeln('${prefix}_latency_microseconds{operation="${e.key}",quantile="0.5"} ${h['p50Us']}');
      buf.writeln('${prefix}_latency_microseconds{operation="${e.key}",quantile="0.95"} ${h['p95Us']}');
      buf.writeln('${prefix}_latency_microseconds{operation="${e.key}",quantile="0.99"} ${h['p99Us']}');
      buf.writeln('${prefix}_latency_microseconds_sum{operation="${e.key}"} ${(h['meanUs'] as int) * (h['count'] as int)}');
      buf.writeln('${prefix}_latency_microseconds_count{operation="${e.key}"} ${h['count']}');
    }

    buf.writeln('# HELP ${prefix}_error_rate Current error rate (0-1)');
    buf.writeln('# TYPE ${prefix}_error_rate gauge');
    buf.writeln('${prefix}_error_rate ${snap.errorRate.toStringAsFixed(4)}');

    buf.writeln('# HELP ${prefix}_uptime_seconds Vault uptime in seconds');
    buf.writeln('# TYPE ${prefix}_uptime_seconds counter');
    buf.writeln('${prefix}_uptime_seconds ${snap.uptimeSeconds}');

    return buf.toString();
  }

  // ── Convenience getters ───────────────────────────────────────────────────

  int operationCount(MetricOperation op) => _opCounters[op]!.value;
  int get totalErrors => _errorCounter.value;
  int get totalReads => _opCounters[MetricOperation.read]!.value;
  int get totalWrites => _opCounters[MetricOperation.write]!.value;
  double get cacheHitRatio {
    final total = _cacheHitCounter.value + _cacheMissCounter.value;
    return total == 0 ? 0.0 : _cacheHitCounter.value / total;
  }

  LatencyHistogram histogramFor(MetricOperation op) => _histograms[op]!;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    stopPeriodicSnapshots();
    await _snapshotStream.close();
  }

  /// Resets ALL counters and histograms.
  void reset() {
    for (final c in _opCounters.values) c.reset();
    for (final h in _histograms.values) h.reset();
    _errorCounter.reset();
    _cacheHitCounter.reset();
    _cacheMissCounter.reset();
    _totalBytesRead.reset();
    _totalBytesWritten.reset();
  }
}
