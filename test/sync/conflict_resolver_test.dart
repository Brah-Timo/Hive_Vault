// test/sync/conflict_resolver_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for conflict resolution strategies.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:test/test.dart';
import '../../lib/src/sync/conflict_resolver.dart';

VersionedValue<T> _vv<T>(
  T value, {
  required String sourceId,
  required DateTime timestamp,
  int version = 1,
  Map<String, int> clock = const {},
}) =>
    VersionedValue<T>(
      value: value,
      sourceId: sourceId,
      timestamp: timestamp,
      version: version,
      vectorClock: clock,
    );

VaultConflict<T> _conflict<T>({
  required String key,
  required T localVal,
  required T remoteVal,
  DateTime? localTs,
  DateTime? remoteTs,
  int localVersion = 1,
  int remoteVersion = 2,
  Map<String, int> localClock = const {},
  Map<String, int> remoteClock = const {},
}) {
  final now = DateTime.now();
  return VaultConflict<T>(
    key: key,
    local: _vv(localVal,
        sourceId: 'local',
        timestamp: localTs ?? now,
        version: localVersion,
        clock: localClock),
    remote: _vv(remoteVal,
        sourceId: 'remote',
        timestamp: remoteTs ?? now.add(const Duration(seconds: 1)),
        version: remoteVersion,
        clock: remoteClock),
  );
}

void main() {
  // ── LastWriteWinsResolver ─────────────────────────────────────────────────

  group('LastWriteWinsResolver', () {
    const resolver = LastWriteWinsResolver<String>();

    test('remote wins when remote is newer', () async {
      final c = _conflict<String>(
        key: 'k',
        localVal: 'old',
        remoteVal: 'new',
        localTs: DateTime(2024, 1, 1),
        remoteTs: DateTime(2024, 1, 2),
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('new'));
      expect(res.strategy, equals(ResolutionStrategy.remoteWins));
    });

    test('local wins when local is newer', () async {
      final c = _conflict<String>(
        key: 'k',
        localVal: 'newer',
        remoteVal: 'older',
        localTs: DateTime(2024, 1, 2),
        remoteTs: DateTime(2024, 1, 1),
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('newer'));
      expect(res.strategy, equals(ResolutionStrategy.localWins));
    });
  });

  // ── FirstWriteWinsResolver ────────────────────────────────────────────────

  group('FirstWriteWinsResolver', () {
    const resolver = FirstWriteWinsResolver<String>();

    test('keeps older value', () async {
      final c = _conflict<String>(
        key: 'k',
        localVal: 'first',
        remoteVal: 'second',
        localTs: DateTime(2024, 1, 1),
        remoteTs: DateTime(2024, 1, 2),
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('first'));
      expect(res.strategy, equals(ResolutionStrategy.localWins));
    });
  });

  // ── RemoteWinsResolver ────────────────────────────────────────────────────

  group('RemoteWinsResolver', () {
    const resolver = RemoteWinsResolver<String>();

    test('always picks remote value', () async {
      final c = _conflict<String>(
        key: 'k',
        localVal: 'local_val',
        remoteVal: 'remote_val',
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('remote_val'));
      expect(res.strategy, equals(ResolutionStrategy.remoteWins));
    });
  });

  // ── LocalWinsResolver ─────────────────────────────────────────────────────

  group('LocalWinsResolver', () {
    const resolver = LocalWinsResolver<String>();

    test('always keeps local value', () async {
      final c = _conflict<String>(
        key: 'k',
        localVal: 'keep_me',
        remoteVal: 'ignore_me',
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('keep_me'));
      expect(res.strategy, equals(ResolutionStrategy.localWins));
    });
  });

  // ── FieldMergeResolver ────────────────────────────────────────────────────

  group('FieldMergeResolver', () {
    test('merges non-conflicting fields', () async {
      final resolver = FieldMergeResolver();
      final c = _conflict<Map<String, dynamic>>(
        key: 'doc',
        localVal: {'name': 'Alice', 'age': 30},
        remoteVal: {'email': 'alice@test.com', 'city': 'London'},
      );
      final res = await resolver.resolve(c);
      expect(res.strategy, equals(ResolutionStrategy.merged));
      expect(res.resolvedValue['name'], equals('Alice'));
      expect(res.resolvedValue['email'], equals('alice@test.com'));
    });

    test('remote wins scalar conflicts by default', () async {
      final resolver = FieldMergeResolver();
      final c = _conflict<Map<String, dynamic>>(
        key: 'doc',
        localVal: {'score': 10},
        remoteVal: {'score': 20},
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue['score'], equals(20));
    });

    test('localPriorityFields keeps local value', () async {
      final resolver = FieldMergeResolver(
        localPriorityFields: {'score'},
      );
      final c = _conflict<Map<String, dynamic>>(
        key: 'doc',
        localVal: {'score': 10},
        remoteVal: {'score': 20},
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue['score'], equals(10));
    });

    test('nested map is merged recursively', () async {
      final resolver = FieldMergeResolver();
      final c = _conflict<Map<String, dynamic>>(
        key: 'doc',
        localVal: {
          'address': {'street': '123 Main St', 'city': 'Springfield'}
        },
        remoteVal: {
          'address': {'city': 'Shelbyville', 'zip': '12345'}
        },
      );
      final res = await resolver.resolve(c);
      final addr = res.resolvedValue['address'] as Map<String, dynamic>;
      expect(addr['street'], equals('123 Main St')); // local-only field kept
      expect(addr['zip'], equals('12345')); // remote-only field added
      expect(
          addr['city'], equals('Shelbyville')); // remote wins scalar conflict
    });
  });

  // ── VersionVectorResolver ─────────────────────────────────────────────────

  group('VersionVectorResolver', () {
    test('local dominates when local clock is causally greater', () async {
      final resolver = VersionVectorResolver<String>();
      final c = _conflict<String>(
        key: 'k',
        localVal: 'local',
        remoteVal: 'remote',
        localClock: {'A': 3, 'B': 2},
        remoteClock: {'A': 2, 'B': 2},
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('local'));
      expect(res.strategy, equals(ResolutionStrategy.localWins));
    });

    test('remote dominates when remote clock is causally greater', () async {
      final resolver = VersionVectorResolver<String>();
      final c = _conflict<String>(
        key: 'k',
        localVal: 'local',
        remoteVal: 'remote',
        localClock: {'A': 1, 'B': 1},
        remoteClock: {'A': 2, 'B': 1},
      );
      final res = await resolver.resolve(c);
      expect(res.resolvedValue, equals('remote'));
      expect(res.strategy, equals(ResolutionStrategy.remoteWins));
    });

    test('concurrent versions fall back to LWW', () async {
      final resolver = VersionVectorResolver<String>();
      // Concurrent: A has higher on one key, B has higher on other
      final now = DateTime.now();
      final c = _conflict<String>(
        key: 'k',
        localVal: 'local',
        remoteVal: 'remote',
        localTs: now,
        remoteTs: now.add(const Duration(seconds: 1)),
        localClock: {'A': 2, 'B': 1},
        remoteClock: {'A': 1, 'B': 2},
      );
      final res = await resolver.resolve(c);
      // Falls back to LWW; remote is newer so remote wins
      expect(res.resolvedValue, equals('remote'));
    });
  });

  // ── DeferredResolver ──────────────────────────────────────────────────────

  group('DeferredResolver', () {
    test('deferred resolution keeps local and queues conflict', () async {
      final resolver = DeferredResolver<String>();
      final c =
          _conflict<String>(key: 'k', localVal: 'local', remoteVal: 'remote');
      final res = await resolver.resolve(c);
      expect(res.strategy, equals(ResolutionStrategy.deferred));
      expect(res.resolvedValue, equals('local'));
      expect(resolver.pendingConflicts.length, equals(1));
    });

    test('resolveManually removes from queue', () async {
      final resolver = DeferredResolver<String>();
      final c = _conflict<String>(key: 'k', localVal: 'a', remoteVal: 'b');
      await resolver.resolve(c);
      resolver.resolveManually('k', 'resolved');
      expect(resolver.pendingConflicts.isEmpty, isTrue);
    });
  });

  // ── ConflictDetector ──────────────────────────────────────────────────────

  group('ConflictDetector', () {
    final now = DateTime.now();
    test('detects conflicts for differing values', () {
      final existing = {
        'k1': _vv('old', sourceId: 'local', timestamp: now, version: 1),
        'k2': _vv('same', sourceId: 'local', timestamp: now, version: 1),
      };
      final incoming = {
        'k1': _vv('new', sourceId: 'remote', timestamp: now, version: 2),
        'k2': _vv('same', sourceId: 'remote', timestamp: now, version: 1),
      };
      final conflicts = ConflictDetector.detect<String>(
        existing: existing,
        incoming: incoming,
      );
      expect(conflicts.length, equals(1));
      expect(conflicts[0].key, equals('k1'));
    });

    test('no conflict for new remote keys', () {
      final existing = <String, VersionedValue<String>>{};
      final incoming = {
        'newKey': _vv('val', sourceId: 'remote', timestamp: now, version: 1),
      };
      final conflicts = ConflictDetector.detect<String>(
        existing: existing,
        incoming: incoming,
      );
      expect(conflicts, isEmpty);
    });
  });

  // ── VersionedValue ────────────────────────────────────────────────────────

  group('VersionedValue', () {
    test('bump increments version', () {
      final vv =
          _vv('value', sourceId: 'A', timestamp: DateTime.now(), version: 3);
      final bumped = vv.bump(newValue: 'new', bySource: 'A');
      expect(bumped.version, equals(4));
      expect(bumped.value, equals('new'));
    });

    test('toJson produces expected keys', () {
      final vv = _vv('x', sourceId: 's', timestamp: DateTime.now());
      final json = vv.toJson();
      expect(json.containsKey('version'), isTrue);
      expect(json.containsKey('sourceId'), isTrue);
      expect(json.containsKey('timestamp'), isTrue);
    });
  });
}
