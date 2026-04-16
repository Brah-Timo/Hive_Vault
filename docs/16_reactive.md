# Reactive Vault

> **File**: `lib/src/impl/reactive_vault.dart`

`ReactiveVault` wraps any `SecureStorageInterface` and emits `VaultEvent` streams on every mutation, enabling Flutter widgets to rebuild automatically when vault data changes.

---

## `VaultEventType`

```dart
enum VaultEventType {
  saved,         // Single secureSave completed
  deleted,       // Single secureDelete completed
  batchSaved,    // secureSaveBatch completed (one event per key)
  batchDeleted,  // secureDeleteBatch completed (one event per key)
  cleared,       // Future: bulk clear (reserved)
}
```

---

## `VaultEvent`

```dart
class VaultEvent {
  final String key;               // The key that changed
  final VaultEventType type;
  final DateTime timestamp;

  @override
  String toString() => 'VaultEvent(${type.name}, key: "$key", at: ...)';
}
```

---

## `ReactiveVault`

```dart
class ReactiveVault implements SecureStorageInterface {
  ReactiveVault(SecureStorageInterface inner);
}
```

Delegates all read operations directly to the inner vault. Only mutation methods (`secureSave`, `secureDelete`, and their batch counterparts) emit events after the delegate completes.

### Stream Access

```dart
// All vault events
Stream<VaultEvent> get watchAll;

// Events for a specific key
Stream<VaultEvent> watch(String key);

// Events for any key in a set
Stream<VaultEvent> watchKeys(Set<String> keys);
```

---

## Usage with Flutter

### `StreamBuilder`

```dart
final reactiveVault = ReactiveVault(await HiveVault.open(...));

// In a widget:
StreamBuilder<VaultEvent>(
  stream: reactiveVault.watch('INVOICE-001'),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      // Reload the invoice
      return FutureBuilder<Map?>(
        future: reactiveVault.secureGet<Map>('INVOICE-001'),
        builder: (context, invSnap) {
          if (!invSnap.hasData) return CircularProgressIndicator();
          final inv = invSnap.data!;
          return InvoiceCard(invoice: inv);
        },
      );
    }
    return Text('No changes yet');
  },
);
```

### With Provider / ChangeNotifier

```dart
class InvoiceNotifier extends ChangeNotifier {
  final ReactiveVault vault;
  Map<String, dynamic>? _current;

  InvoiceNotifier(this.vault, String invoiceId) {
    vault.watch(invoiceId).listen((_) async {
      _current = await vault.secureGet<Map<String, dynamic>>(invoiceId);
      notifyListeners();
    });
  }

  Map<String, dynamic>? get invoice => _current;
}
```

### Watch Multiple Keys

```dart
reactiveVault
    .watchKeys({'INV-001', 'INV-002', 'INV-003'})
    .listen((event) {
      print('${event.key} was ${event.type.name}');
      // Reload affected invoices
    });
```

### Watch All Changes

```dart
reactiveVault.watchAll.listen((event) {
  print('Vault changed: ${event.key} (${event.type.name})');
});
```

---

## Wrap an Existing Vault

```dart
// Any SecureStorageInterface can be wrapped:
final baseVault = await HiveVault.open(
  boxName: 'invoices',
  config: VaultConfig.erp(),
);
final reactive = ReactiveVault(baseVault);

// Use reactive for reads/writes
await reactive.secureSave('INV-001', data);
// ↑ Also emits: VaultEvent(saved, key: "INV-001")

final value = await reactive.secureGet<Map>('INV-001');
// ↑ No event emitted (reads are transparent)
```

---

## Lifecycle

```dart
// Close ReactiveVault: closes the broadcast stream controller AND the inner vault
await reactive.close();
// After close(), new subscriptions will receive no events
// Existing subscriptions receive the stream's close signal
```

---

## Batch Event Emission

For batch operations, one event is emitted **per key** (not a single batch event):

```dart
await reactive.secureSaveBatch({
  'A': valueA,
  'B': valueB,
  'C': valueC,
});
// Emits:
//   VaultEvent(saved, key: "A")
//   VaultEvent(saved, key: "B")
//   VaultEvent(saved, key: "C")
```

This allows listeners to filter on specific keys rather than receiving a bulk notification.

---

## Composing ReactiveVault with Other Wrappers

`ReactiveVault` implements `SecureStorageInterface`, so it can be used anywhere a vault is expected:

```dart
// ReactiveVault wrapping a ShardManager
final reactive = ReactiveVault(shardManager);

// ReactiveVault wrapping a vault inside a MultiBoxVault
final erp = MultiBoxVault(modules: ['invoices']);
await erp.initialize();
final reactiveInvoices = ReactiveVault(erp['invoices']);
```
