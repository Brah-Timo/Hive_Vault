// lib/src/impl/migration_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Schema migration manager.
// Runs versioned migrations when the payload format changes between releases.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:hive/hive.dart';
import '../core/vault_exceptions.dart';

/// A single migration step: upgrades payload data from [fromVersion] to
/// [toVersion].
abstract class VaultMigration {
  /// The payload version this migration reads from.
  int get fromVersion;

  /// The payload version this migration produces.
  int get toVersion;

  /// Transforms [oldPayload] into the new format.
  ///
  /// The returned bytes must be a valid HiveVault payload at [toVersion].
  Future<Uint8List> migrate(Uint8List oldPayload);

  /// Human-readable description of what this migration does.
  String get description;
}

/// Manages a chain of [VaultMigration] steps and applies them to a Hive box.
class MigrationManager {
  /// Ordered list of migrations (oldest → newest).
  final List<VaultMigration> _migrations;

  /// Key used to store the current schema version in a dedicated Hive box.
  static const String _versionBoxName = '__hive_vault_schema__';
  static const String _versionKey = 'schema_version';

  const MigrationManager(this._migrations);

  /// Returns the schema version stored on disk (0 if never migrated).
  static Future<int> getCurrentVersion() async {
    try {
      final box = await Hive.openBox<int>(_versionBoxName);
      return box.get(_versionKey, defaultValue: 0)!;
    } catch (_) {
      return 0;
    }
  }

  /// Persists the new schema version.
  static Future<void> setCurrentVersion(int version) async {
    final box = await Hive.openBox<int>(_versionBoxName);
    await box.put(_versionKey, version);
  }

  /// Runs all pending migrations on [box] starting from [currentVersion].
  ///
  /// Only migrations with [VaultMigration.fromVersion] ≥ [currentVersion]
  /// are executed. Migrations run in order.
  ///
  /// Throws [VaultStorageException] if a migration fails. The box is left in
  /// a consistent (partially migrated) state — run again to continue.
  Future<void> migrate(
    Box<Uint8List> box,
    int currentVersion,
    int targetVersion,
  ) async {
    if (currentVersion >= targetVersion) return;

    final pending = _migrations
        .where((m) =>
            m.fromVersion >= currentVersion &&
            m.toVersion <= targetVersion)
        .toList()
      ..sort((a, b) => a.fromVersion.compareTo(b.fromVersion));

    if (pending.isEmpty) return;

    print('HiveVault: running ${pending.length} migration(s) '
        'v$currentVersion → v$targetVersion');

    for (final migration in pending) {
      print('  → ${migration.description}');
      for (final rawKey in List<dynamic>.from(box.keys)) {
        final key = rawKey as String;
        final payload = box.get(key);
        if (payload == null) continue;
        try {
          final migrated = await migration.migrate(payload);
          await box.put(key, migrated);
        } catch (e) {
          throw VaultStorageException(
            'Migration failed for key "$key" '
            '(v${migration.fromVersion} → v${migration.toVersion})',
            cause: e,
          );
        }
      }
      await setCurrentVersion(migration.toVersion);
      print('  ✅ Migration to v${migration.toVersion} complete');
    }
  }
}
