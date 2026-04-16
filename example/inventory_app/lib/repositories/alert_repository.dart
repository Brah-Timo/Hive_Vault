// example/inventory_app/lib/repositories/alert_repository.dart

import '../models/stock_alert.dart';
import 'vault_repository.dart';

class AlertRepository extends VaultRepository<StockAlert> {
  AlertRepository(super.vault);



  static const _prefix = 'alert:';

  @override
  String keyFor(StockAlert item) => '$_prefix${item.id}';

  @override
  Map<String, dynamic> toMap(StockAlert item) => item.toMap();

  @override
  StockAlert fromMap(Map<String, dynamic> map) => StockAlert.fromMap(map);

  Future<List<StockAlert>> getAllAlerts() async {
    final keys = (await vault.getAllKeys())
        .where((k) => k.startsWith(_prefix))
        .toList();
    if (keys.isEmpty) return [];
    final maps = await vault.secureGetBatch(keys);
    final alerts = maps.values
        .whereType<Map<String, dynamic>>()
        .map(StockAlert.fromMap)
        .toList();
    alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return alerts;
  }

  Future<List<StockAlert>> getActiveAlerts() async {
    final all = await getAllAlerts();
    return all.where((a) => !a.isDismissed).toList();
  }

  Future<List<StockAlert>> getUnreadAlerts() async {
    final all = await getAllAlerts();
    return all.where((a) => !a.isRead && !a.isDismissed).toList();
  }

  Future<int> getUnreadCount() async {
    final unread = await getUnreadAlerts();
    return unread.length;
  }

  Future<void> markAllRead() async {
    final all = await getAllAlerts();
    for (final alert in all) {
      if (!alert.isRead) {
        alert.markRead();
        await save(alert);
      }
    }
  }

  Future<void> dismissAlert(String alertId) async {
    final alert = await get('$_prefix$alertId');
    if (alert != null) {
      alert.dismiss();
      await save(alert);
    }
  }

  Future<bool> alertExistsForProduct(
      String productId, AlertType type) async {
    final all = await getActiveAlerts();
    return all.any((a) =>
        a.productId == productId && a.type == type && !a.isDismissed);
  }

  Future<void> deleteOldAlerts({int keepDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    final all = await getAllAlerts();
    for (final alert in all) {
      if (alert.createdAt.isBefore(cutoff)) {
        await delete(keyFor(alert));
      }
    }
  }

  // saveRaw / getRaw are inherited from VaultRepository base class.
}
