# Example: Inventory ERP App

> **Directory**: `example/inventory_app/`

A complete Flutter inventory management system demonstrating all HiveVault features in a real-world ERP context.

---

## App Architecture

```
example/inventory_app/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── product.dart
│   │   ├── supplier.dart
│   │   ├── category.dart
│   │   ├── purchase_order.dart
│   │   ├── stock_movement.dart
│   │   └── alert.dart
│   ├── repositories/
│   │   ├── product_repository.dart
│   │   ├── supplier_repository.dart
│   │   ├── category_repository.dart
│   │   ├── order_repository.dart
│   │   └── stock_movement_repository.dart
│   ├── services/
│   │   └── inventory_service.dart
│   ├── providers/
│   │   └── inventory_provider.dart
│   └── screens/
│       ├── dashboard/
│       ├── products/
│       ├── suppliers/
│       ├── orders/
│       └── settings/
```

---

## Models

### `Supplier`

```dart
class Supplier {
  final String id;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? taxNumber;
  final String? notes;
  final int leadTimeDays;        // Default delivery lead time
  final double rating;           // 1.0 – 5.0
  final bool isActive;
  final DateTime createdAt;
}
```

### `Product`

```dart
class Product {
  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final double price;
  final double cost;
  final int stockQuantity;
  final int reorderPoint;        // Trigger reorder below this
  final int reorderQuantity;     // Order this many units
  final bool isActive;
}
```

### `PurchaseOrder`

```dart
class PurchaseOrder {
  final String id;
  final String orderNumber;      // e.g., "PO-2024-0042"
  final String supplierId;
  final String supplierName;
  final DateTime orderDate;
  final DateTime? expectedDelivery;
  final String? notes;
  final List<PurchaseOrderLine> lines;
  final String status;           // draft/sent/partial/received/cancelled
  final DateTime? receivedDate;
  final double totalAmount;
  final String createdBy;
}
```

---

## Repositories

Each repository extends `VaultRepository<T>` which wraps a `SecureStorageInterface` and provides typed CRUD:

```dart
abstract class VaultRepository<T> {
  final SecureStorageInterface vault;

  String keyFor(String id);
  Map<String, dynamic> toMap(T entity);
  T fromMap(Map<String, dynamic> map);
  String searchableText(T entity);

  Future<void> save(T entity);
  Future<T?> getById(String id);
  Future<List<T>> getAll();
  Future<void> delete(String id);
}
```

### `SupplierRepository`

```dart
class SupplierRepository extends VaultRepository<Supplier> {
  String keyFor(String id) => 'supplier:$id';

  String searchableText(Supplier s) =>
      '${s.name} ${s.contactName ?? ''} ${s.email ?? ''}';

  Future<Supplier?> getById(String id) async;
  Future<List<Supplier>> getAllSuppliers() async;
  Future<List<Supplier>> getActiveSuppliers() async;  // isActive == true
}
```

Keys use the `supplier:` prefix, enabling `searchPrefix('supplier:')` to list all suppliers efficiently.

---

## `InventoryProvider` (ChangeNotifier)

Central state manager for the app, consuming all repositories:

### State

```dart
class InventoryProvider extends ChangeNotifier {
  List<Product> products = [];
  List<Supplier> suppliers = [];
  List<Category> categories = [];
  List<PurchaseOrder> orders = [];
  List<StockMovement> recentMovements = [];
  List<Alert> alerts = [];
  DashboardSummary? summary;

  // Filters (managed by UI)
  String searchText = '';
  String? selectedCategoryId;
  String? selectedStatusFilter;

  // Computed
  List<Product> get filteredProducts;
  Category? getCategoryById(String id);
  Supplier? getSupplierById(String id);
}
```

### Initialization

```dart
Future<void> initialize() async {
  await _loadCategories();
  await Future.wait([
    _loadProducts(),
    _loadSuppliers(),
    _loadRecentMovements(),
    _loadOrders(),
    _loadAlerts(),
  ]);
  await _updateDashboardSummary();
}
```

### Supplier CRUD

```dart
Future<void> saveSupplier(Supplier supplier) async {
  await _supplierRepo.save(supplier);
  await _loadSuppliers();        // Reload supplier list
  notifyListeners();
}

Future<void> deleteSupplier(String id) async {
  await _supplierRepo.delete(id);
  await _loadSuppliers();
  notifyListeners();
}
```

### Purchase Order Operations

```dart
Future<void> createPurchaseOrder(PurchaseOrder order) async;
Future<void> updateOrderStatus(String orderId, String status) async;
Future<void> receiveOrder(String orderId, Map<String, int> receivedQties) async;
Future<int> createReorderRequests() async;  // Auto-create POs for low stock
```

### Stock Movements

```dart
Future<void> recordStockMovement(StockMovement movement) async {
  await _stockService.record(movement);
  await Future.wait([
    _loadProducts(),       // Refresh stock quantities
    _loadRecentMovements(),
    _loadAlerts(),
  ]);
  notifyListeners();
}
```

---

## Screens

### Suppliers Screen (`suppliers_screen.dart`)

Full CRUD UI for supplier management:

- **List view**: sortable, searchable supplier list with activity indicator
- **Add supplier**: `showAddSupplierForm(context)` shows a `DraggableScrollableSheet` modal
- **Edit supplier**: `_SupplierEditForm` via `showModalBottomSheet`
- **Delete supplier**: swipe-to-delete with confirmation dialog
- **Detail view**: opens `SupplierDetailScreen` on tap

```dart
// Adding a new supplier (called from Purchase Order form too)
void showAddSupplierForm(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => ChangeNotifierProvider.value(
      value: context.read<InventoryProvider>(),
      child: _SupplierForm(),     // ← Provider correctly inherited
    ),
    isScrollControlled: true,
  );
}
```

### Purchase Order Form (`purchase_order_form_screen.dart`)

- Supplier dropdown (shows active suppliers only)
- When no suppliers exist: shows `_NoSupplierCard` with "Create Supplier" button
- "Add New Supplier" quick link → calls `suppliersScreen.showAddSupplierForm()`
- Line items: add products, set quantity and unit cost
- Total amount auto-calculated
- Generates order number: `PO-<year>-<sequence>` format

```dart
// _NoSupplierCard: shown when supplier list is empty
class _NoSupplierCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    child: Column(children: [
      Icon(Icons.business_outlined, size: 48),
      Text('No suppliers yet'),
      ElevatedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SuppliersScreen()),
        ).then((_) => context.read<InventoryProvider>().loadSuppliers()),
        child: Text('Create First Supplier'),
      ),
    ]),
  );
}
```

---

## HiveVault Configuration Used

```dart
// In inventory_service.dart
final vault = await HiveVault.open(
  boxName: 'inventory_erp',
  config: VaultConfig.erp(),   // GZip-6, AES-256-GCM, full index, cache=200
);
```

### Search Used

```dart
// Full-text search across products
final results = await vault.secureSearch<Map>('widget a');

// Search by barcode
Future<Product?> getByBarcode(String barcode) async {
  final keys = await vault.searchKeys(barcode);
  if (keys.isEmpty) return null;
  final map = await vault.secureGet<Map>(keys.first);
  return map != null ? Product.fromMap(map) : null;
}
```

### Key Prefixes

| Domain | Key prefix | Example |
|---|---|---|
| Products | `product:` | `product:PROD-001` |
| Suppliers | `supplier:` | `supplier:SUP-042` |
| Categories | `category:` | `category:electronics` |
| Orders | `order:` | `order:PO-2024-0042` |
| Movements | `movement:` | `movement:MOV-2024-03-15-001` |
| Alerts | `alert:` | `alert:low_stock_PROD-001` |

---

## Running the Example

```bash
cd example/inventory_app
flutter pub get
flutter run
```

Requirements:
- Flutter ≥ 3.10.0
- Dart ≥ 3.0.0
- Android / iOS / macOS / Windows / Linux (Hive supported on all)
