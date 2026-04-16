// lib/src/plugin/vault_plugin.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Plugin / Middleware System.
//
// Allows third-party code (or app-layer logic) to hook into vault operations
// without modifying the core library. Each plugin can intercept:
//
//   • beforeSave   / afterSave
//   • beforeGet    / afterGet
//   • beforeDelete / afterDelete
//   • onError
//   • onInitialize / onClose
//
// Plugins are executed in registration order. A plugin may:
//   • Transform the value (e.g., field-level masking, schema validation).
//   • Reject the operation by throwing a [VaultPluginException].
//   • Observe silently (logging, analytics).
//
// Usage:
//   ```dart
//   final vault = PluggableVault(inner: hiveVaultImpl)
//     ..use(SchemaValidatorPlugin(schema: userSchema))
//     ..use(FieldMaskingPlugin(fields: ['ssn', 'password']))
//     ..use(AuditWebhookPlugin(url: 'https://logs.example.com'));
//   ```
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import '../core/vault_interface.dart';
import '../core/vault_exceptions.dart';
import '../core/sensitivity_level.dart';
import '../core/vault_stats.dart';
import '../audit/audit_entry.dart';
import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════════════════
//  Plugin context
// ═══════════════════════════════════════════════════════════════════════════

/// Mutable context passed to each plugin hook so plugins can mutate values
/// and signal cancellation.
class PluginContext {
  final String key;
  dynamic value;
  SensitivityLevel? sensitivity;
  String? searchableText;
  bool cancelled = false;
  String? cancellationReason;
  final Map<String, dynamic> extras = {};

  PluginContext({
    required this.key,
    this.value,
    this.sensitivity,
    this.searchableText,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Plugin interface
// ═══════════════════════════════════════════════════════════════════════════

/// Abstract base for all HiveVault plugins.
///
/// Override only the hooks you need; all methods have no-op defaults.
abstract class VaultPlugin {
  /// Human-readable name of this plugin.
  String get name;

  /// Priority (lower number = earlier execution). Default: 100.
  int get priority => 100;

  /// Called once when the vault is initialized.
  Future<void> onInitialize() async {}

  /// Called once when the vault is closed.
  Future<void> onClose() async {}

  /// Called before a value is saved. Mutate [ctx] to transform the value.
  /// Set [ctx.cancelled = true] to abort the save.
  Future<void> beforeSave(PluginContext ctx) async {}

  /// Called after a value is successfully saved.
  Future<void> afterSave(PluginContext ctx) async {}

  /// Called before a value is retrieved. Set [ctx.cancelled = true] to
  /// return null instead of reading.
  Future<void> beforeGet(PluginContext ctx) async {}

  /// Called after a value is retrieved. [ctx.value] holds the decoded value.
  Future<void> afterGet(PluginContext ctx) async {}

  /// Called before a key is deleted.
  Future<void> beforeDelete(PluginContext ctx) async {}

  /// Called after a key is deleted.
  Future<void> afterDelete(PluginContext ctx) async {}

  /// Called when any vault operation throws an error.
  Future<void> onError(PluginContext ctx, Object error) async {}

  @override
  String toString() => 'VaultPlugin($name, priority: $priority)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  Plugin registry
// ═══════════════════════════════════════════════════════════════════════════

/// Manages an ordered list of [VaultPlugin] instances.
class PluginRegistry {
  final List<VaultPlugin> _plugins = [];

  /// Registers [plugin] and sorts by priority.
  void register(VaultPlugin plugin) {
    _plugins.add(plugin);
    _plugins.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Removes a plugin by name.
  void unregister(String name) {
    _plugins.removeWhere((p) => p.name == name);
  }

  /// Returns the plugin with [name], or null.
  VaultPlugin? find(String name) =>
      _plugins.cast<VaultPlugin?>().firstWhere(
            (p) => p?.name == name,
            orElse: () => null,
          );

  List<VaultPlugin> get all => List.unmodifiable(_plugins);
  int get count => _plugins.length;

  // ── Hook dispatchers ──────────────────────────────────────────────────────

  Future<void> runOnInitialize() async {
    for (final p in _plugins) {
      await p.onInitialize();
    }
  }

  Future<void> runOnClose() async {
    for (final p in _plugins) {
      await p.onClose();
    }
  }

  Future<PluginContext> runBeforeSave(PluginContext ctx) async {
    for (final p in _plugins) {
      if (ctx.cancelled) break;
      await p.beforeSave(ctx);
    }
    return ctx;
  }

  Future<void> runAfterSave(PluginContext ctx) async {
    for (final p in _plugins) {
      await p.afterSave(ctx);
    }
  }

  Future<PluginContext> runBeforeGet(PluginContext ctx) async {
    for (final p in _plugins) {
      if (ctx.cancelled) break;
      await p.beforeGet(ctx);
    }
    return ctx;
  }

  Future<PluginContext> runAfterGet(PluginContext ctx) async {
    for (final p in _plugins) {
      await p.afterGet(ctx);
    }
    return ctx;
  }

  Future<PluginContext> runBeforeDelete(PluginContext ctx) async {
    for (final p in _plugins) {
      if (ctx.cancelled) break;
      await p.beforeDelete(ctx);
    }
    return ctx;
  }

  Future<void> runAfterDelete(PluginContext ctx) async {
    for (final p in _plugins) {
      await p.afterDelete(ctx);
    }
  }

  Future<void> runOnError(PluginContext ctx, Object error) async {
    for (final p in _plugins) {
      try {
        await p.onError(ctx, error);
      } catch (_) {}
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Pluggable vault decorator
// ═══════════════════════════════════════════════════════════════════════════

/// A [SecureStorageInterface] decorator that runs registered plugins on
/// every operation.
///
/// Wrap any vault implementation:
/// ```dart
/// final vault = PluggableVault(inner: rawVault)
///   ..use(LoggingPlugin())
///   ..use(ValidationPlugin(schema: mySchema));
/// ```
class PluggableVault implements SecureStorageInterface {
  final SecureStorageInterface _inner;
  final PluginRegistry _registry = PluginRegistry();

  PluggableVault({required SecureStorageInterface inner}) : _inner = inner;

  /// Registers [plugin] with this vault.
  PluggableVault use(VaultPlugin plugin) {
    _registry.register(plugin);
    return this;
  }

  /// Removes the plugin with [name].
  void removePlugin(String name) => _registry.unregister(name);

  /// Returns the underlying plugin registry (for inspection).
  PluginRegistry get plugins => _registry;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    await _inner.initialize();
    await _registry.runOnInitialize();
  }

  @override
  Future<void> close() async {
    await _registry.runOnClose();
    await _inner.close();
  }

  // ── Core CRUD ─────────────────────────────────────────────────────────────

  @override
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  }) async {
    final ctx = PluginContext(
      key: key,
      value: value,
      sensitivity: sensitivity,
      searchableText: searchableText,
    );
    try {
      await _registry.runBeforeSave(ctx);
      if (ctx.cancelled) {
        throw VaultPluginException(
          'Save for "$key" was cancelled by plugin: ${ctx.cancellationReason}',
        );
      }
      await _inner.secureSave(
        key,
        ctx.value as T,
        sensitivity: ctx.sensitivity,
        searchableText: ctx.searchableText,
      );
      await _registry.runAfterSave(ctx);
    } catch (e) {
      await _registry.runOnError(ctx, e);
      rethrow;
    }
  }

  @override
  Future<T?> secureGet<T>(String key) async {
    final ctx = PluginContext(key: key);
    try {
      await _registry.runBeforeGet(ctx);
      if (ctx.cancelled) return null;

      final value = await _inner.secureGet<T>(key);
      ctx.value = value;
      await _registry.runAfterGet(ctx);
      return ctx.value as T?;
    } catch (e) {
      await _registry.runOnError(ctx, e);
      rethrow;
    }
  }

  @override
  Future<void> secureDelete(String key) async {
    final ctx = PluginContext(key: key);
    try {
      await _registry.runBeforeDelete(ctx);
      if (ctx.cancelled) return;
      await _inner.secureDelete(key);
      await _registry.runAfterDelete(ctx);
    } catch (e) {
      await _registry.runOnError(ctx, e);
      rethrow;
    }
  }

  // ── Delegation (no plugin hooks needed) ───────────────────────────────────

  @override
  Future<bool> secureContains(String key) => _inner.secureContains(key);

  @override
  Future<List<String>> getAllKeys() => _inner.getAllKeys();

  @override
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  }) async {
    for (final e in entries.entries) {
      await secureSave(e.key, e.value, sensitivity: sensitivity);
    }
  }

  @override
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys) async {
    final result = <String, dynamic>{};
    for (final k in keys) {
      final v = await secureGet<dynamic>(k);
      if (v != null) result[k] = v;
    }
    return result;
  }

  @override
  Future<void> secureDeleteBatch(List<String> keys) async {
    for (final k in keys) {
      await secureDelete(k);
    }
  }

  @override
  Future<List<T>> secureSearch<T>(String query) =>
      _inner.secureSearch<T>(query);

  @override
  Future<List<T>> secureSearchAny<T>(String query) =>
      _inner.secureSearchAny<T>(query);

  @override
  Future<List<T>> secureSearchPrefix<T>(String prefix) =>
      _inner.secureSearchPrefix<T>(prefix);

  @override
  Future<Set<String>> searchKeys(String query) => _inner.searchKeys(query);

  @override
  Future<void> rebuildIndex() => _inner.rebuildIndex();

  @override
  Future<void> compact() => _inner.compact();

  @override
  void clearCache() => _inner.clearCache();

  @override
  Future<Uint8List> exportEncrypted() => _inner.exportEncrypted();

  @override
  Future<void> importEncrypted(Uint8List data) =>
      _inner.importEncrypted(data);

  @override
  Future<VaultStats> getStats() => _inner.getStats();

  @override
  List<AuditEntry> getAuditLog({int limit = 50}) =>
      _inner.getAuditLog(limit: limit);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Built-in plugins
// ═══════════════════════════════════════════════════════════════════════════

/// Plugin that logs all vault operations to the console (debug builds).
class ConsoleLoggingPlugin extends VaultPlugin {
  @override
  String get name => 'console_logging';

  @override
  int get priority => 10; // Run early so all ops are logged.

  final bool verbose;
  ConsoleLoggingPlugin({this.verbose = false});

  @override
  Future<void> beforeSave(PluginContext ctx) async {
    if (verbose) print('[HiveVault] SAVE key="${ctx.key}"');
  }

  @override
  Future<void> afterGet(PluginContext ctx) async {
    if (verbose) print('[HiveVault] GET  key="${ctx.key}" hit=${ctx.value != null}');
  }

  @override
  Future<void> afterDelete(PluginContext ctx) async {
    if (verbose) print('[HiveVault] DEL  key="${ctx.key}"');
  }

  @override
  Future<void> onError(PluginContext ctx, Object error) async {
    print('[HiveVault] ERROR key="${ctx.key}": $error');
  }
}

/// Plugin that masks specified fields in Map values before writing.
/// Useful for PII protection (e.g., mask 'password', 'ssn', 'card').
class FieldMaskingPlugin extends VaultPlugin {
  final Set<String> maskedFields;
  final String maskValue;

  FieldMaskingPlugin({
    required this.maskedFields,
    this.maskValue = '***',
  });

  @override
  String get name => 'field_masking';

  @override
  int get priority => 20;

  @override
  Future<void> beforeSave(PluginContext ctx) async {
    if (ctx.value is Map<String, dynamic>) {
      final map = Map<String, dynamic>.from(ctx.value as Map<String, dynamic>);
      for (final field in maskedFields) {
        if (map.containsKey(field)) {
          map[field] = maskValue;
        }
      }
      ctx.value = map;
    }
  }
}

/// Plugin that validates Map values against a simple schema before saving.
///
/// [schema] is a map of field → expected Dart type (e.g., {'age': int}).
class SchemaValidationPlugin extends VaultPlugin {
  final Map<String, Type> requiredFields;

  SchemaValidationPlugin({required this.requiredFields});

  @override
  String get name => 'schema_validation';

  @override
  int get priority => 5; // Run before masking.

  @override
  Future<void> beforeSave(PluginContext ctx) async {
    if (ctx.value is! Map<String, dynamic>) return;
    final map = ctx.value as Map<String, dynamic>;
    for (final entry in requiredFields.entries) {
      final field = entry.key;
      final expectedType = entry.value;
      if (!map.containsKey(field)) {
        ctx.cancelled = true;
        ctx.cancellationReason =
            'Schema validation: required field "$field" is missing';
        return;
      }
      if (map[field].runtimeType != expectedType) {
        ctx.cancelled = true;
        ctx.cancellationReason =
            'Schema validation: field "$field" expected $expectedType '
            'but got ${map[field].runtimeType}';
        return;
      }
    }
  }
}

/// Plugin that enforces a key naming convention.
class KeyNamingPlugin extends VaultPlugin {
  final RegExp pattern;
  final String description;

  KeyNamingPlugin({required this.pattern, required this.description});

  @override
  String get name => 'key_naming';

  @override
  int get priority => 1; // Run first.

  @override
  Future<void> beforeSave(PluginContext ctx) async {
    if (!pattern.hasMatch(ctx.key)) {
      ctx.cancelled = true;
      ctx.cancellationReason =
          'Key "${ctx.key}" does not match naming convention: $description';
    }
  }
}

/// Plugin that collects per-operation timing metrics.
class TimingPlugin extends VaultPlugin {
  @override
  String get name => 'timing';

  final Map<String, List<int>> _timings = {};

  @override
  Future<void> beforeSave(PluginContext ctx) async {
    ctx.extras['_saveStart'] = DateTime.now().microsecondsSinceEpoch;
  }

  @override
  Future<void> afterSave(PluginContext ctx) async {
    final start = ctx.extras['_saveStart'] as int?;
    if (start != null) {
      final elapsed = DateTime.now().microsecondsSinceEpoch - start;
      (_timings['save'] ??= []).add(elapsed);
    }
  }

  @override
  Future<void> beforeGet(PluginContext ctx) async {
    ctx.extras['_getStart'] = DateTime.now().microsecondsSinceEpoch;
  }

  @override
  Future<void> afterGet(PluginContext ctx) async {
    final start = ctx.extras['_getStart'] as int?;
    if (start != null) {
      final elapsed = DateTime.now().microsecondsSinceEpoch - start;
      (_timings['get'] ??= []).add(elapsed);
    }
  }

  /// Returns average timing (µs) for [operation] ('save' | 'get').
  double averageUs(String operation) {
    final list = _timings[operation];
    if (list == null || list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  Map<String, double> get averages => {
        for (final entry in _timings.entries)
          entry.key: entry.value.isEmpty
              ? 0.0
              : entry.value.reduce((a, b) => a + b) / entry.value.length,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
//  Plugin exception
// ═══════════════════════════════════════════════════════════════════════════

/// Thrown when a plugin cancels or rejects a vault operation.
class VaultPluginException extends VaultException {
  const VaultPluginException(super.message, {super.cause});

  @override
  String toString() => 'VaultPluginException: $message'
      '${cause != null ? '\n  Caused by: $cause' : ''}';
}
