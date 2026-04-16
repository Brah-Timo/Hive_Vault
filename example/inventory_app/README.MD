# InventoryVault — Complete Flutter Inventory Management System

A full-featured, **offline-first** inventory management app built with Flutter and the **HiveVault** secure storage library. All data is stored locally and encrypted with AES-256-GCM.

---

## ✨ Features

| Feature | Details |
|---|---|
| 🔐 Encrypted Storage | AES-256-GCM via HiveVault (7 isolated vaults) |
| 📦 Product Management | Full CRUD, barcode, SKU, categories, suppliers |
| 📊 Dashboard | KPI cards, pie chart, low-stock list, recent movements |
| 📱 Barcode Scanner | Camera-based (mobile/desktop) + manual entry (web) |
| 🔔 Smart Alerts | Low stock, out-of-stock, reorder required notifications |
| 🚚 Stock Movements | 8 movement types with full audit trail |
| 📋 Purchase Orders | 7 status stages, receive workflow |
| 📈 Reports | Low stock, valuation, movements, reorder — with PDF export |
| 🔢 Inventory Count | Stocktake with variance reconciliation |
| 🔍 Global Search | Across products, suppliers, categories |
| ⚙️ Settings | Notification preferences, currency, display options |
| 🔑 PIN Auth | 4-digit PIN protection with shake animation |
| 👥 Team Roles | Admin / Manager / Operator / Viewer RBAC |
| 🌐 Web-Safe | All features work in Flutter Web (camera fallback, no dart:io) |

---

## 🏗️ Architecture

```
lib/
├── main.dart                    # App entry point, vault initialisation
├── models/                      # Data models (Product, Category, Supplier, ...)
├── repositories/                # HiveVault-backed typed repositories
├── services/
│   ├── vault_service.dart       # Manages all 7 HiveVault instances
│   ├── stock_service.dart       # Stock movement business logic
│   ├── report_service.dart      # Report generation
│   ├── notification_service.dart # Web-safe local notifications
│   ├── auth_service.dart        # PIN authentication
│   └── pdf_service.dart         # PDF generation & printing
├── providers/
│   └── inventory_provider.dart  # Central ChangeNotifier
├── screens/
│   ├── dashboard/               # Dashboard with KPIs & charts
│   ├── products/                # Product list, form, detail
│   ├── stock/                   # Stock movements & inventory count
│   ├── orders/                  # Purchase orders
│   ├── suppliers/               # Supplier management
│   ├── categories/              # Category management
│   ├── alerts/                  # Stock alerts
│   ├── reports/                 # All reports with PDF export
│   ├── scanner/                 # Barcode scanner (web-safe)
│   ├── search/                  # Global search
│   ├── settings/                # App settings
│   ├── auth/                    # PIN authentication screen
│   ├── team/                    # Team member management
│   └── onboarding/              # 5-step onboarding walkthrough
├── theme/                       # Material 3 theme
├── utils/                       # Formatters, route constants
└── widgets/                     # Reusable widgets
```

---

## 🔒 HiveVault Configuration

| Vault | Encryption | Compression | Purpose |
|---|---|---|---|
| `inv_products` | AES-256-GCM | GZip / LZ4 (web) | Products |
| `inv_categories` | AES-256-CBC | LZ4 | Categories |
| `inv_movements` | AES-256-CBC | GZip / LZ4 (web) | Stock movements |
| `inv_suppliers` | AES-256-GCM | GZip / LZ4 (web) | Suppliers |
| `inv_orders` | AES-256-GCM | GZip / LZ4 (web) | Purchase orders |
| `inv_alerts` | AES-256-CBC | LZ4 | Stock alerts |
| `inv_settings` | AES-256-GCM (200k PBKDF2) | GZip / LZ4 (web) | Settings & auth |

---

## 🚀 Getting Started

```bash
# 1. Clone the repository
git clone https://github.com/GPT4-AI/hive_vault.git
cd hive_vault

# 2. Navigate to the example app
cd example/inventory_app

# 3. Install dependencies
flutter pub get

# 4. Run on web (quick start)
flutter run -d web-server --web-port 8080

# 5. Run on Android
flutter run -d android

# 6. Run on iOS
flutter run -d ios
```

---

## 🌐 Web Support

The app is fully web-compatible:

- **Compression**: Uses LZ4 (pure-Dart) on web instead of dart:io GZip/ZLib
- **Barcode Scanner**: Shows manual entry field on web (camera still supported in modern browsers via mobile_scanner ≥ 5.2.3)  
- **Notifications**: Silently skipped on web (flutter_local_notifications is mobile-only)
- **PDF**: Uses `printing` package which supports web via browser print dialog

---

## 📋 Changelog

### v1.3.0 — 2026-04-16
- **Improved Material 3 theme**: Google Fonts (Inter), better dark theme, `CardTheme` replaces deprecated `CardThemeData`, improved button styles, snackbar & dialog themes
- **Full routing**: Added `onGenerateRoute` for parameterised routes (`productDetail`, `supplierDetail`, `purchaseOrderDetail`, `auth`)
- **Swipe-to-delete products**: `ProductCard` now wraps with `Slidable` when `onDelete` callback is provided
- **Audit log in Settings**: Vault Statistics dialog shows real metrics (entries, reads, writes, cache hit rate)
- **Team Management link**: Added to main drawer and Settings screen
- **Web scanner stub**: `scanner_stub.dart` replaces `mobile_scanner` on web builds (conditional import)
- **Fixed `withOpacity` deprecation**: Key widgets updated to use `withAlpha()`
- **Improved ProductCard**: Color-coded stock indicator, location tag, status tag, better action buttons

### v1.2.0 — Previous
- **Web-safe scanner**: Camera view only shown on native; web shows manual barcode/SKU entry  
- **Web-safe inventory count**: Replaced embedded MobileScanner with manual lookup on web  
- **Web-safe notifications**: `flutter_local_notifications` calls are now guarded with `kIsWeb`  
- **Improved onboarding**: 5-page walkthrough with animated progress indicators, demo data loader
- **Fixed `InventorySummary.empty`**: Replaced `const` sentinel with a regular getter to avoid `_EpochDate` workaround  
- **Auth screen**: 4-digit PIN with shake animation, lockout after 5 attempts
- **Team management**: RBAC roles (Admin/Manager/Operator/Viewer)

### v1.1.0 — Previous
- All compression providers changed from `implements` to `extends`  
- Fixed `${prefix}_operations_total` interpolation in `vault_metrics.dart`  
- Corrected `ReactiveVault` return types (exportEncrypted, getStats, getAuditLog)  
- Added `dispose()` overrides to all encryption providers  
- Added `const` constructors to `CompressionProvider` and `EncryptionProvider`  
- Made GZip/Deflate web-safe via conditional IO codec shims

---

## 📦 Dependencies

```yaml
hive_vault: (path: ../..)   # AES-256-GCM encrypted storage
mobile_scanner: ^5.2.3      # Barcode scanning (supports web via ZXing)
fl_chart: ^0.70.2           # Charts (pie, bar)
pdf + printing:             # PDF generation and printing
provider: ^6.1.2            # State management
flutter_local_notifications # Push notifications (mobile only)
barcode_widget:             # Barcode rendering
```
