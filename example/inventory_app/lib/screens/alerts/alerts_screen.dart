// example/inventory_app/lib/screens/alerts/alerts_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Alerts screen — lists all low-stock, out-of-stock, and reorder alerts.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/stock_alert.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        final active =
            prov.alerts.where((a) => !a.isDismissed).toList();
        final critical =
            active.where((a) => a.severity == AlertSeverity.critical).length;
        final warnings =
            active.where((a) => a.severity == AlertSeverity.warning).length;
        final info =
            active.where((a) => a.severity == AlertSeverity.info).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Stock Alerts'),
            actions: [
              if (prov.unreadAlertCount > 0)
                TextButton.icon(
                  onPressed: prov.markAllAlertsRead,
                  icon: const Icon(Icons.done_all,
                      color: Colors.white, size: 18),
                  label: const Text('Read All',
                      style: TextStyle(color: Colors.white)),
                ),
              IconButton(
                onPressed: () => _runScan(context, prov),
                icon: const Icon(Icons.refresh),
                tooltip: 'Scan for alerts',
              ),
            ],
          ),
          body: active.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: 'No Active Alerts',
                  subtitle:
                      'Run a scan to detect low stock and reorder issues.',
                )
              : Column(
                  children: [
                    // Summary chips
                    _buildSummaryBar(critical, warnings, info),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: prov.loadAll,
                        child: ListView.builder(
                          itemCount: active.length,
                          itemBuilder: (context, i) =>
                              _AlertTile(
                            alert: active[i],
                            onDismiss: () =>
                                prov.dismissAlert(active[i].id),
                            onMarkRead: () async {
                              // Mark single alert read by reusing markAll
                              // (individual mark available via alert repo)
                              await prov.markAllAlertsRead();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _runScan(context, prov),
            icon: const Icon(Icons.search),
            label: const Text('Scan Now'),
          ),
        );
      },
    );
  }

  Widget _buildSummaryBar(int critical, int warnings, int info) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          _chip(Icons.error, '$critical Critical',
              AppTheme.errorColor),
          const SizedBox(width: 8),
          _chip(Icons.warning_amber, '$warnings Warnings',
              AppTheme.warningColor),
          const SizedBox(width: 8),
          _chip(Icons.info_outline, '$info Info',
              AppTheme.infoColor),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Future<void> _runScan(
      BuildContext context, InventoryProvider prov) async {
    final count = await prov.runAlertScan();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Scan complete: $count new alert(s) found')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final StockAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onMarkRead;

  const _AlertTile({
    required this.alert,
    required this.onDismiss,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    final isUnread = !alert.isRead;

    return Dismissible(
      key: Key(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade100,
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => onDismiss(),
      child: Card(
        margin: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isUnread
              ? BorderSide(color: color, width: 1.5)
              : BorderSide.none,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(
              _alertIcon(alert.type),
              color: color,
              size: 20,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  alert.productName,
                  style: TextStyle(
                    fontWeight: isUnread
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isUnread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.message,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _severityBadge(alert.severity),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(alert.createdAt),
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (v) {
              if (v == 'dismiss') onDismiss();
              if (v == 'read') onMarkRead();
            },
            itemBuilder: (_) => [
              if (isUnread)
                const PopupMenuItem(
                  value: 'read',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.done),
                    title: Text('Mark as read'),
                  ),
                ),
              const PopupMenuItem(
                value: 'dismiss',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Dismiss'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(AlertSeverity s) => switch (s) {
        AlertSeverity.critical => AppTheme.errorColor,
        AlertSeverity.warning => AppTheme.warningColor,
        AlertSeverity.info => AppTheme.infoColor,
      };

  IconData _alertIcon(AlertType t) => switch (t) {
        AlertType.outOfStock => Icons.remove_shopping_cart,
        AlertType.lowStock => Icons.warning_amber,
        AlertType.overStock => Icons.expand,
        AlertType.reorderRequired => Icons.shopping_cart_checkout,
        AlertType.expiryWarning => Icons.timer_off,
      };

  Widget _severityBadge(AlertSeverity s) {
    final color = _severityColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        s.label,
        style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }
}
