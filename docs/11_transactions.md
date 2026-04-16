# Transaction System

> **File**: `lib/src/transaction/vault_transaction.dart`

HiveVault provides an ACID-style transaction system with a write-ahead log (WAL), savepoints, and automatic rollback on failure.

---

## ACID Properties

| Property | How HiveVault achieves it |
|---|---|
| **Atomicity** | Either all writes in a transaction are committed or none (rollback discards the WAL) |
| **Consistency** | Vault remains in a valid state after commit or rollback |
| **Isolation** | Read-your-writes: a transaction sees its own pending writes; concurrent isolates see only committed data |
| **Durability** | `commit()` calls `secureSave/Delete` which persist to Hive; Hive itself uses ACID file writes |

---

## `TransactionStatus`

```dart
enum TransactionStatus { active, committed, rolledBack }
```

---

## `_TxOperation` (Internal)

Represents a single operation in the write-ahead log:

```dart
class _TxOperation {
  final String key;
  final dynamic value;          // null for delete operations
  final SensitivityLevel? sensitivity;
  final String? searchableText;
  final DateTime timestamp;
  final bool isDelete;
}
```

---

## `TransactionSavepoint`

Named checkpoint within a transaction for partial rollback:

```dart
class TransactionSavepoint {
  final String name;
  final int walIndex;   // WAL index at savepoint creation
  final DateTime createdAt;
}
```

---

## `VaultTransaction`

The main transaction object. Created by `VaultTransactionManager.begin()`.

```dart
class VaultTransaction {
  final String id;                           // Unique transaction ID (UUID)
  TransactionStatus get status;              // active / committed / rolledBack
  int get pendingWrites;                     // Number of write operations in WAL
  List<String> get pendingKeys;             // Keys with pending operations
}
```

### Write Operations

```dart
// Stage a write (not persisted until commit())
void write(
  String key,
  dynamic value, {
  SensitivityLevel? sensitivity,
  String? searchableText,
});

// Stage a delete
void delete(String key);
```

### Read Operations (Read-your-writes)

```dart
// Read a value: returns pending write if exists, else reads from vault
Future<T?> read<T>(
  String key,
  SecureStorageInterface vault,
);

// Check if key exists (considering pending writes/deletes)
Future<bool> contains(String key, SecureStorageInterface vault);
```

### Savepoints

```dart
// Create a named savepoint at the current WAL position
TransactionSavepoint savepoint(String name);

// Rollback all operations since the savepoint
void rollbackToSavepoint(TransactionSavepoint sp);
```

### Commit

```dart
Future<TransactionReceipt> commit(SecureStorageInterface vault) async
```

Execution:
1. Assert status is `active`
2. For each operation in the WAL (in order):
   - `isDelete == true` → `vault.secureDelete(key)`
   - `isDelete == false` → `vault.secureSave(key, value, ...)`
3. Set `status = committed`
4. Return `TransactionReceipt`

On any error during commit: throws and leaves transaction in `active` state (partial commit possible — design your operations to be idempotent or use savepoints).

### Rollback

```dart
void rollback()
// Sets status = rolledBack, clears WAL
// No changes were persisted (WAL was never applied)
```

---

## `TransactionReceipt`

Immutable record of a completed transaction:

```dart
@immutable
class TransactionReceipt {
  final String id;
  final int writes;           // Number of write operations committed
  final int deletes;          // Number of delete operations committed
  final Duration elapsed;     // Wall-clock time from begin to commit
  final TransactionStatus status;
  final DateTime? committedAt;
}
```

---

## `VaultTransactionManager`

Factory and registry for active transactions:

```dart
class VaultTransactionManager {
  // Create a new transaction
  VaultTransaction begin();

  // Auto-commit/rollback wrapper
  Future<TransactionReceipt> runInTransaction(
    SecureStorageInterface vault,
    Future<void> Function(VaultTransaction tx) action,
  );

  // Introspection
  List<VaultTransaction> get activeTransactions;
  int get totalTransactionCount;
}
```

### `runInTransaction`

Wraps the action in a try/catch:
- If `action` completes without error: calls `tx.commit(vault)`
- If `action` throws: calls `tx.rollback()`, then re-throws the error

```dart
final manager = VaultTransactionManager();

final receipt = await manager.runInTransaction(vault, (tx) async {
  tx.write('ORDER-001', orderData);
  tx.write('STOCK-PROD-A', stockData);   // Decrement stock
  tx.delete('DRAFT-001');
  // If any of the above fail, ALL are rolled back
});

print('Committed: ${receipt.writes} writes in ${receipt.elapsed.inMilliseconds}ms');
```

---

## Usage Examples

### Basic Transaction

```dart
final manager = VaultTransactionManager();
final tx = manager.begin();

tx.write('INVOICE-001', invoice);
tx.write('PAYMENT-001', payment);
tx.write('LEDGER-2024-Q1', updatedLedger);

try {
  final receipt = await tx.commit(vault);
  print('Committed ${receipt.writes} entries');
} catch (e) {
  tx.rollback();
  print('Transaction failed: $e');
}
```

### With Savepoints

```dart
final tx = manager.begin();

tx.write('DRAFT-HEADER', headerData);
final sp = tx.savepoint('after_header');

tx.write('DRAFT-LINE-1', line1);
tx.write('DRAFT-LINE-2', line2);

if (!validationPassed) {
  // Undo lines but keep header
  tx.rollbackToSavepoint(sp);
}

await tx.commit(vault);
```

### Read-your-writes

```dart
final tx = manager.begin();

// Stage a write
tx.write('PROD-001', {'name': 'Widget', 'stock': 100});

// Read back the staged value (not yet in vault)
final staged = await tx.read<Map>('PROD-001', vault);
print(staged?['stock']);  // 100 — from WAL, not from vault

await tx.commit(vault);
```

### `runInTransaction` Convenience

```dart
await manager.runInTransaction(vault, (tx) async {
  final order = await tx.read<Map>('ORDER-123', vault);
  if (order == null) throw Exception('Order not found');

  tx.write('ORDER-123', {...order, 'status': 'fulfilled'});
  tx.write('FULFILLMENT-456', fulfillmentData);
  // Auto-commits; auto-rolls-back on exception
});
```

---

## `VaultTransactionException`

```dart
class VaultTransactionException extends VaultException {
  const VaultTransactionException(String message, {Object? cause});
}
```

Thrown when:
- Attempting to write to a committed or rolled-back transaction
- Attempting to commit a non-active transaction
- Attempting to rollback-to-savepoint after the savepoint no longer exists
