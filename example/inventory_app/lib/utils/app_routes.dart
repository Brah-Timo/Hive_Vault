// example/inventory_app/lib/utils/app_routes.dart
// ─────────────────────────────────────────────────────────────────────────────
// Named route constants for the entire app.
// ─────────────────────────────────────────────────────────────────────────────

class AppRoutes {
  AppRoutes._();

  // ── Core ──────────────────────────────────────────────────────────────────
  static const onboarding = '/onboarding';
  static const dashboard = '/';

  // ── Products ──────────────────────────────────────────────────────────────
  static const products = '/products';
  static const productDetail = '/products/detail';
  static const productForm = '/products/form';

  // ── Scanner ───────────────────────────────────────────────────────────────
  static const scanner = '/scanner';

  // ── Search ────────────────────────────────────────────────────────────────
  static const search = '/search';

  // ── Categories ────────────────────────────────────────────────────────────
  static const categories = '/categories';

  // ── Stock ─────────────────────────────────────────────────────────────────
  static const stockMovements = '/stock/movements';
  static const stockMovementForm = '/stock/movement/form';
  static const inventoryCount = '/stock/count';

  // ── Alerts ────────────────────────────────────────────────────────────────
  static const alerts = '/alerts';

  // ── Purchase Orders ───────────────────────────────────────────────────────
  static const purchaseOrders = '/orders';
  static const purchaseOrderDetail = '/orders/detail';
  static const purchaseOrderForm = '/orders/form';

  // ── Suppliers ─────────────────────────────────────────────────────────────
  static const suppliers = '/suppliers';
  static const supplierDetail = '/suppliers/detail';
  static const supplierForm = '/suppliers/form';

  // ── Reports ───────────────────────────────────────────────────────────────
  static const reports = '/reports';
  static const reportLowStock = '/reports/low-stock';
  static const reportValuation = '/reports/valuation';
  static const reportMovements = '/reports/movements';
  static const reportReorder = '/reports/reorder';
  static const reportSummary = '/reports/summary';

  // ── Settings ──────────────────────────────────────────────────────────────
  static const settings = '/settings';

  // ── Team Management ───────────────────────────────────────────────────────
  static const team = '/team';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const auth = '/auth';
}
