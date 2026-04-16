// example/inventory_app/lib/services/notification_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Local notifications for stock alerts & reorder reminders.
// Web-safe: notifications are silently ignored on Flutter Web because
// flutter_local_notifications does not support Web.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/stock_alert.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _channelId = 'inventory_alerts';
  static const _channelName = 'Inventory Alerts';
  static const _channelDesc = 'Low stock and reorder notifications';

  Future<void> initialize() async {
    // flutter_local_notifications is not supported on Web.
    if (kIsWeb) return;
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // Gracefully ignore initialisation errors (e.g., on desktop in debug).
    }
  }

  Future<void> showAlertNotification(StockAlert alert) async {
    if (kIsWeb || !_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        alert.id.hashCode,
        _titleForAlert(alert),
        alert.message,
        details,
      );
    } catch (_) {}
  }

  Future<void> showBatchAlertSummary(int count) async {
    if (kIsWeb || !_initialized || count == 0) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _plugin.show(
        0,
        'Inventory Alert',
        '$count product(s) require attention',
        details,
      );
    } catch (_) {}
  }

  String _titleForAlert(StockAlert alert) => switch (alert.type) {
        AlertType.outOfStock => 'Out of Stock',
        AlertType.lowStock => 'Low Stock Warning',
        AlertType.reorderRequired => 'Reorder Required',
        AlertType.overStock => 'Overstock Warning',
        AlertType.expiryWarning => 'Expiry Warning',
      };

  Future<void> cancelAll() async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
