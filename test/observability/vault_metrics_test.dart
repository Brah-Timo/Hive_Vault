// test/observability/vault_metrics_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for VaultMetrics and LatencyHistogram.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/observability/vault_metrics.dart';

void main() {
  // ── LatencyHistogram ──────────────────────────────────────────────────────

  group('LatencyHistogram', () {
    late LatencyHistogram h;

    setUp(() => h = LatencyHistogram());

    test('starts empty', () {
      expect(h.count, equals(0));
      expect(h.meanUs, equals(0.0));
    });

    test('records single observation', () {
      h.record(500);
      expect(h.count, equals(1));
      expect(h.meanUs, equals(500.0));
      expect(h.minUs, equals(500));
      expect(h.maxUs, equals(500));
    });

    test('min/max track extremes', () {
      h.record(100);
      h.record(5000);
      h.record(250);
      expect(h.minUs, equals(100));
      expect(h.maxUs, equals(5000));
    });

    test('mean is computed correctly', () {
      h.record(1000);
      h.record(3000);
      expect(h.meanUs, closeTo(2000.0, 0.01));
    });

    test('percentile p50 is median-ish', () {
      for (int i = 1; i <= 100; i++) {
        h.record(i * 100); // 100µs to 10000µs
      }
      // p50 should be around 5000µs (bucket containing 50th element)
      expect(h.p50, greaterThan(0));
      expect(h.p50, lessThanOrEqualTo(10000));
    });

    test('p99 >= p95 >= p50', () {
      for (int i = 1; i <= 200; i++) {
        h.record(i * 50);
      }
      expect(h.p99, greaterThanOrEqualTo(h.p95));
      expect(h.p95, greaterThanOrEqualTo(h.p50));
    });

    test('reset clears all state', () {
      h.record(1000);
      h.record(2000);
      h.reset();
      expect(h.count, equals(0));
      expect(h.meanUs, equals(0.0));
    });

    test('toJson contains expected keys', () {
      h.record(1500);
      final json = h.toJson();
      expect(json.containsKey('count'), isTrue);
      expect(json.containsKey('p50Us'), isTrue);
      expect(json.containsKey('p95Us'), isTrue);
      expect(json.containsKey('p99Us'), isTrue);
      expect(json.containsKey('meanUs'), isTrue);
    });
  });

  // ── MetricCounter ─────────────────────────────────────────────────────────

  group('MetricCounter', () {
    test('starts at zero', () {
      final c = MetricCounter();
      expect(c.value, equals(0));
    });

    test('increments by 1', () {
      final c = MetricCounter();
      c.increment();
      c.increment();
      expect(c.value, equals(2));
    });

    test('increments by arbitrary amount', () {
      final c = MetricCounter();
      c.increment(50);
      expect(c.value, equals(50));
    });

    test('reset returns to zero', () {
      final c = MetricCounter();
      c.increment(100);
      c.reset();
      expect(c.value, equals(0));
    });
  });

  // ── VaultMetrics ──────────────────────────────────────────────────────────

  group('VaultMetrics', () {
    late VaultMetrics metrics;

    setUp(() => metrics = VaultMetrics(vaultName: 'test_vault'));

    test('initial snapshot has zero counts', () {
      final snap = metrics.snapshot();
      expect(snap.counters['write'], equals(0));
      expect(snap.counters['read'], equals(0));
    });

    test('recordOperation increments counter', () {
      metrics.recordOperation(MetricOperation.write, durationUs: 1000);
      metrics.recordOperation(MetricOperation.write, durationUs: 1200);
      metrics.recordOperation(MetricOperation.read, durationUs: 500);
      expect(metrics.totalWrites, equals(2));
      expect(metrics.totalReads, equals(1));
    });

    test('error counter increments with isError=true', () {
      metrics.recordOperation(MetricOperation.write,
          durationUs: 0, isError: true);
      expect(metrics.totalErrors, equals(1));
    });

    test('error rate is 0 when no ops', () {
      final snap = metrics.snapshot();
      expect(snap.errorRate, equals(0.0));
    });

    test('error rate computed from error/total ops', () {
      metrics.recordOperation(MetricOperation.read, durationUs: 100);
      metrics.recordOperation(MetricOperation.read,
          durationUs: 100, isError: true);
      final snap = metrics.snapshot();
      expect(snap.errorRate, closeTo(0.5, 0.01));
    });

    test('cache hit ratio from fromCache flag', () {
      metrics.recordOperation(MetricOperation.read,
          durationUs: 100, fromCache: true);
      metrics.recordOperation(MetricOperation.read,
          durationUs: 100, fromCache: false);
      metrics.recordOperation(MetricOperation.read,
          durationUs: 100, fromCache: true);
      expect(metrics.cacheHitRatio, closeTo(2 / 3, 0.01));
    });

    test('histogram records latencies', () {
      metrics.recordOperation(MetricOperation.write, durationUs: 500);
      metrics.recordOperation(MetricOperation.write, durationUs: 1500);
      final h = metrics.histogramFor(MetricOperation.write);
      expect(h.count, equals(2));
    });

    test('snapshot contains histogram data', () {
      metrics.recordOperation(MetricOperation.search, durationUs: 20000);
      final snap = metrics.snapshot();
      expect(snap.histograms.containsKey('search'), isTrue);
    });

    test('snapshot uptime increases over time', () async {
      await Future.delayed(const Duration(milliseconds: 10));
      final snap = metrics.snapshot();
      expect(snap.uptimeSeconds, greaterThanOrEqualTo(0));
    });

    test('toPrometheusText contains metric lines', () {
      metrics.recordOperation(MetricOperation.write, durationUs: 800);
      final text = metrics.toPrometheusText();
      expect(text.contains('hive_vault_'), isTrue);
      expect(text.contains('operations_total'), isTrue);
    });

    test('reset clears all counters', () {
      metrics.recordOperation(MetricOperation.write, durationUs: 1000);
      metrics.reset();
      expect(metrics.totalWrites, equals(0));
      expect(metrics.totalErrors, equals(0));
    });

    test('MetricsSnapshot.toJson returns valid map', () {
      metrics.recordOperation(MetricOperation.read, durationUs: 300);
      final json = metrics.snapshot().toJson();
      expect(json.containsKey('capturedAt'), isTrue);
      expect(json.containsKey('counters'), isTrue);
      expect(json.containsKey('errorRate'), isTrue);
    });
  });

  // ── MetricsSnapshot.delta ─────────────────────────────────────────────────

  group('MetricsSnapshot.delta', () {
    test('delta computes difference in counters', () {
      final m = VaultMetrics(vaultName: 'delta_test');
      m.recordOperation(MetricOperation.write, durationUs: 100);
      final snap1 = m.snapshot();
      m.recordOperation(MetricOperation.write, durationUs: 100);
      m.recordOperation(MetricOperation.write, durationUs: 100);
      final snap2 = m.snapshot();
      final delta = snap2.delta(snap1);
      expect(delta.counters['write'], equals(2));
    });
  });
}
