# Plugin System

> **File**: `lib/src/plugin/vault_plugin.dart`

The plugin system provides lifecycle hooks that allow extending HiveVault with custom behaviour without modifying the core implementation.

---

## `VaultPlugin` (Abstract)

```dart
abstract class VaultPlugin {
  /// Plugin identifier for logging and diagnostics.
  String get name;

  /// Priority order: lower numbers run first.
  /// Default: 100
  int get priority => 100;

  // ── Lifecycle hooks ────────────────────────────────────────────────────

  /// Called once after the vault is fully initialized.
  Future<void> onInitialize(SecureStorageInterface vault) async {}

  /// Called once before the vault is closed.
  Future<void> onClose(SecureStorageInterface vault) async {}

  // ── Write hooks ────────────────────────────────────────────────────────

  /// Called before every secureSave. Return modified key/value or null to skip.
  Future<PluginWriteResult?> beforeWrite(String key, dynamic value) async => null;

  /// Called after every successful secureSave.
  Future<void> afterWrite(String key, dynamic value) async {}

  // ── Read hooks ─────────────────────────────────────────────────────────

  /// Called before every secureGet.
  Future<void> beforeRead(String key) async {}

  /// Called after every successful secureGet. Return modified value.
  Future<dynamic> afterRead(String key, dynamic value) async => value;

  // ── Delete hooks ───────────────────────────────────────────────────────

  /// Called before every secureDelete.
  Future<void> beforeDelete(String key) async {}

  /// Called after every successful secureDelete.
  Future<void> afterDelete(String key) async {}

  // ── Search hooks ───────────────────────────────────────────────────────

  /// Called before every search operation.
  Future<void> beforeSearch(String query) async {}

  /// Called after every search. Return modified results.
  Future<List<dynamic>> afterSearch(String query, List<dynamic> results) async => results;

  // ── Error hook ─────────────────────────────────────────────────────────

  /// Called when any vault operation throws an exception.
  Future<void> onError(String operation, String key, Object error) async {}
}
```

---

## `PluginWriteResult`

Returned by `beforeWrite` to control the write operation:

```dart
class PluginWriteResult {
  final String key;        // Possibly modified key
  final dynamic value;     // Possibly modified value
  final bool skip;         // Set true to cancel the write entirely
}
```

---

## `VaultPluginRegistry`

Manages a sorted collection of plugins:

```dart
class VaultPluginRegistry {
  void register(VaultPlugin plugin);
  void unregister(String pluginName);
  bool isRegistered(String name);

  List<VaultPlugin> get plugins;  // Sorted by priority ascending
}
```

---

## Example Plugins

### Logging Plugin

```dart
class LoggingPlugin extends VaultPlugin {
  @override
  String get name => 'logging';

  @override
  int get priority => 10;  // Run first

  @override
  Future<void> afterWrite(String key, dynamic value) async {
    print('[VaultPlugin] Written: $key');
  }

  @override
  Future<void> afterDelete(String key) async {
    print('[VaultPlugin] Deleted: $key');
  }

  @override
  Future<void> onError(String op, String key, Object error) async {
    print('[VaultPlugin] Error in $op($key): $error');
  }
}
```

### Key Validation Plugin

```dart
class KeyValidationPlugin extends VaultPlugin {
  @override
  String get name => 'key_validation';

  @override
  Future<PluginWriteResult?> beforeWrite(String key, dynamic value) async {
    if (!RegExp(r'^[A-Z]+-\d+$').hasMatch(key)) {
      throw VaultStorageException(
        'Invalid key format: "$key". Expected: "PREFIX-123"',
      );
    }
    return null;  // Allow write with unchanged key/value
  }
}
```

### Encryption Audit Plugin

```dart
class EncryptionAuditPlugin extends VaultPlugin {
  @override
  String get name => 'encryption_audit';

  final Set<String> _writtenKeys = {};

  @override
  Future<void> afterWrite(String key, dynamic value) async {
    _writtenKeys.add(key);
  }

  @override
  Future<void> afterDelete(String key) async {
    _writtenKeys.remove(key);
  }

  Set<String> get auditedKeys => Set.unmodifiable(_writtenKeys);
}
```

### Value Transformation Plugin

```dart
class SanitizationPlugin extends VaultPlugin {
  @override
  String get name => 'sanitization';

  @override
  Future<PluginWriteResult?> beforeWrite(String key, dynamic value) async {
    if (value is Map<String, dynamic>) {
      // Strip all null values before storing
      final cleaned = Map<String, dynamic>.from(value)
        ..removeWhere((k, v) => v == null);
      return PluginWriteResult(key: key, value: cleaned, skip: false);
    }
    return null;
  }
}
```

---

## Plugin Registration

```dart
final registry = VaultPluginRegistry();
registry.register(LoggingPlugin());
registry.register(KeyValidationPlugin());
registry.register(SanitizationPlugin());

// Query
bool active = registry.isRegistered('logging');
List<VaultPlugin> all = registry.plugins;  // Sorted by priority

// Deregister
registry.unregister('logging');
```

---

## Execution Order

Plugins are executed in `priority` order (ascending). When multiple plugins have the same priority, they run in registration order.

```
Write operation:
  1. Plugin A (priority 10) beforeWrite
  2. Plugin B (priority 50) beforeWrite
  3. Plugin C (priority 100) beforeWrite
  → actual vault.secureSave()
  4. Plugin A (priority 10) afterWrite
  5. Plugin B (priority 50) afterWrite
  6. Plugin C (priority 100) afterWrite
```

If any `beforeWrite` throws, the write is cancelled and subsequent plugins' `beforeWrite` are not called. The `onError` hook is called instead.
