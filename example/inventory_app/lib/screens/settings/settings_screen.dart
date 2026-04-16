// example/inventory_app/lib/screens/settings/settings_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Full settings screen — notifications, display, theme, security,
// data management, backup/restore, and vault statistics.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:hive_vault/hive_vault.dart' show VaultStats;
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../services/vault_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart' show AppTheme, themeNotifier;
import '../../utils/formatters.dart';
import '../auth/auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Notifications
  bool _lowStockNotif = true;
  bool _outOfStockNotif = true;
  bool _reorderNotif = true;
  bool _orderStatusNotif = true;

  // Display
  String _currency = 'USD';
  bool _showCostPrice = true;
  bool _compactMode = false;
  String _themeMode = 'system'; // 'light', 'dark', 'system'

  // Security
  bool _pinEnabled = false;

  // Vault stats
  bool _loadingStats = false;
  Map<String, dynamic>? _vaultStats;

  final List<String> _currencies = [
    'USD',
    'EUR',
    'GBP',
    'SAR',
    'AED',
    'EGP',
    'JPY',
    'CNY',
    'INR'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prov = context.read<InventoryProvider>();
    final prefs = await prov.loadSettings();
    if (mounted) {
      setState(() {
        _lowStockNotif = prefs['lowStockNotif'] as bool? ?? true;
        _outOfStockNotif = prefs['outOfStockNotif'] as bool? ?? true;
        _reorderNotif = prefs['reorderNotif'] as bool? ?? true;
        _orderStatusNotif = prefs['orderStatusNotif'] as bool? ?? true;
        _currency = prefs['currency'] as String? ?? 'USD';
        _showCostPrice = prefs['showCostPrice'] as bool? ?? true;
        _compactMode = prefs['compactMode'] as bool? ?? false;
        _themeMode = prefs['themeMode'] as String? ?? 'system';
        _pinEnabled = AuthService.instance.isPinEnabled;
        // Apply persisted theme immediately
        themeNotifier.value = switch (_themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      });
    }
  }

  Future<void> _saveSettings() async {
    final prov = context.read<InventoryProvider>();
    await prov.saveSettings({
      'lowStockNotif': _lowStockNotif,
      'outOfStockNotif': _outOfStockNotif,
      'reorderNotif': _reorderNotif,
      'orderStatusNotif': _orderStatusNotif,
      'currency': _currency,
      'showCostPrice': _showCostPrice,
      'compactMode': _compactMode,
      'themeMode': _themeMode,
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _loadVaultStats() async {
    setState(() => _loadingStats = true);
    try {
      final stats = await VaultService().getCombinedStats();
      setState(() {
        _vaultStats = {
          'totalItems': stats.totalEntries,
          'cacheHitRate': stats.cacheHitRatio * 100.0,
          'avgReadMs': 0.0,
          'avgWriteMs': 0.0,
        };
      });
    } catch (_) {
      setState(() => _vaultStats = null);
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          _buildHeader(),
          const SizedBox(height: 4),

          // ── Theme ───────────────────────────────────────────────────────
          _sectionTitle('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blueGrey.withOpacity(0.12),
                  child: const Icon(Icons.palette_outlined,
                      color: Colors.blueGrey, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Theme',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'light',
                        icon: Icon(Icons.wb_sunny_outlined, size: 16),
                        label: Text('Light', style: TextStyle(fontSize: 11))),
                    ButtonSegment(
                        value: 'system',
                        icon: Icon(Icons.phone_android_outlined, size: 16),
                        label: Text('Auto', style: TextStyle(fontSize: 11))),
                    ButtonSegment(
                        value: 'dark',
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                        label: Text('Dark', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (v) {
                    setState(() => _themeMode = v.first);
                    themeNotifier.value = switch (v.first) {
                      'light' => ThemeMode.light,
                      'dark' => ThemeMode.dark,
                      _ => ThemeMode.system,
                    };
                  },
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          // ── Notifications ───────────────────────────────────────────────
          _sectionTitle('Notifications'),
          _switchTile(
            title: 'Low Stock Alerts',
            subtitle: 'Notify when stock falls below minimum',
            icon: Icons.warning_amber_outlined,
            iconColor: AppTheme.warningColor,
            value: _lowStockNotif,
            onChanged: (v) => setState(() => _lowStockNotif = v),
          ),
          _switchTile(
            title: 'Out of Stock Alerts',
            subtitle: 'Notify when a product reaches zero',
            icon: Icons.remove_shopping_cart_outlined,
            iconColor: AppTheme.errorColor,
            value: _outOfStockNotif,
            onChanged: (v) => setState(() => _outOfStockNotif = v),
          ),
          _switchTile(
            title: 'Reorder Reminders',
            subtitle: 'Notify when stock hits reorder point',
            icon: Icons.refresh_outlined,
            iconColor: AppTheme.infoColor,
            value: _reorderNotif,
            onChanged: (v) => setState(() => _reorderNotif = v),
          ),
          _switchTile(
            title: 'Order Status Changes',
            subtitle: 'Notify on purchase order updates',
            icon: Icons.shopping_cart_outlined,
            iconColor: AppTheme.primaryColor,
            value: _orderStatusNotif,
            onChanged: (v) => setState(() => _orderStatusNotif = v),
          ),

          // ── Display ─────────────────────────────────────────────────────
          _sectionTitle('Display'),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
              child: const Icon(Icons.attach_money,
                  color: AppTheme.primaryColor, size: 20),
            ),
            title: const Text('Currency'),
            subtitle: Text(_currency),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showCurrencyPicker,
          ),
          _switchTile(
            title: 'Show Cost Price',
            subtitle: 'Display purchase cost in product cards',
            icon: Icons.price_change_outlined,
            iconColor: AppTheme.secondaryColor,
            value: _showCostPrice,
            onChanged: (v) => setState(() => _showCostPrice = v),
          ),
          _switchTile(
            title: 'Compact Mode',
            subtitle: 'Denser product list for small screens',
            icon: Icons.view_compact_outlined,
            iconColor: Colors.blueGrey,
            value: _compactMode,
            onChanged: (v) => setState(() => _compactMode = v),
          ),

          // ── Security ────────────────────────────────────────────────────
          _sectionTitle('Security & Storage'),
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: const Color(0xFF6A1B9A).withOpacity(0.12),
              child: const Icon(Icons.pin_outlined,
                  color: Color(0xFF6A1B9A), size: 20),
            ),
            title: const Text('PIN Protection'),
            subtitle: Text(_pinEnabled
                ? 'App is protected with PIN'
                : 'Require PIN on launch'),
            value: _pinEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (v) => _handlePinToggle(v),
          ),
          if (_pinEnabled)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6A1B9A).withOpacity(0.12),
                child: const Icon(Icons.change_circle_outlined,
                    color: Color(0xFF6A1B9A), size: 20),
              ),
              title: const Text('Change PIN'),
              subtitle: const Text('Set a new 4-digit PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePin,
            ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
              child: const Icon(Icons.lock_outlined,
                  color: AppTheme.primaryColor, size: 20),
            ),
            title: const Text('Encryption'),
            subtitle: const Text('AES-256-GCM — All data encrypted at rest'),
            trailing:
                const Icon(Icons.verified_user, color: AppTheme.successColor),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.infoColor.withOpacity(0.12),
              child: const Icon(Icons.compress_outlined,
                  color: AppTheme.infoColor, size: 20),
            ),
            title: const Text('Compression'),
            subtitle: const Text(
                'GZip (native) / LZ4 (web) — enabled on movements vault'),
          ),
          ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.secondaryColor.withOpacity(0.12),
              child: const Icon(Icons.analytics_outlined,
                  color: AppTheme.secondaryColor, size: 20),
            ),
            title: const Text('Vault Statistics'),
            subtitle: const Text('Tap to view performance metrics'),
            onExpansionChanged: (open) {
              if (open && _vaultStats == null) _loadVaultStats();
            },
            children: [
              if (_loadingStats)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else if (_vaultStats != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    _statRow('Total Items', '${_vaultStats!['totalItems']}'),
                    _statRow('Cache Hit Rate',
                        '${(_vaultStats!['cacheHitRate'] as double? ?? 0.0).toStringAsFixed(1)}%'),
                    _statRow('Avg Read',
                        '${(_vaultStats!['avgReadMs'] as double? ?? 0.0).toStringAsFixed(2)} ms'),
                    _statRow('Avg Write',
                        '${(_vaultStats!['avgWriteMs'] as double? ?? 0.0).toStringAsFixed(2)} ms'),
                    _statRow('Encryption', 'AES-256-GCM'),
                    _statRow('Key Derivation', 'PBKDF2-HMAC-SHA256'),
                  ]),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Could not load stats',
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),

          // ── Data Management ─────────────────────────────────────────────
          _sectionTitle('Data Management'),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.withOpacity(0.12),
              child:
                  const Icon(Icons.data_object, color: Colors.orange, size: 20),
            ),
            title: const Text('Load Demo Data'),
            subtitle: const Text('Seed sample products for testing'),
            onTap: _loadDemoData,
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.infoColor.withOpacity(0.12),
              child: const Icon(Icons.refresh,
                  color: AppTheme.infoColor, size: 20),
            ),
            title: const Text('Run Alert Scan'),
            subtitle: const Text('Check all products for stock issues'),
            onTap: _runAlertScan,
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.infoColor.withOpacity(0.12),
              child: const Icon(Icons.shopping_cart_checkout,
                  color: AppTheme.infoColor, size: 20),
            ),
            title: const Text('Create Reorder Requests'),
            subtitle: const Text('Auto-generate POs for low stock items'),
            onTap: _createReorderRequests,
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.successColor.withOpacity(0.12),
              child: const Icon(Icons.backup_outlined,
                  color: AppTheme.successColor, size: 20),
            ),
            title: const Text('Export Data Backup'),
            subtitle: const Text('Download encrypted backup of all data'),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.warningColor.withOpacity(0.12),
              child: const Icon(Icons.restore_outlined,
                  color: AppTheme.warningColor, size: 20),
            ),
            title: const Text('Restore from Backup'),
            subtitle: const Text('Import previously exported backup'),
            onTap: _importBackup,
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.errorColor.withOpacity(0.12),
              child: const Icon(Icons.delete_forever,
                  color: AppTheme.errorColor, size: 20),
            ),
            title: const Text('Clear All Data',
                style: TextStyle(color: AppTheme.errorColor)),
            subtitle: const Text('Delete all products, movements and alerts'),
            onTap: _confirmClearData,
          ),

          // ── Audit Log ────────────────────────────────────────────────────
          _sectionTitle('Audit & Diagnostics'),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A0288D1),
              child: Icon(Icons.history, color: AppTheme.infoColor, size: 20),
            ),
            title: const Text('Audit Log'),
            subtitle: const Text('View vault read/write/delete operations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAuditLog(context),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A6A1B9A),
              child: Icon(Icons.group_outlined,
                  color: Color(0xFF6A1B9A), size: 20),
            ),
            title: const Text('Team Management'),
            subtitle: const Text('Manage user roles and permissions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/team'),
          ),

          // ── About ───────────────────────────────────────────────────────
          _sectionTitle('About'),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x1A1565C0),
              child: Icon(Icons.code, color: AppTheme.primaryColor, size: 20),
            ),
            title: const Text('InventoryVault'),
            subtitle: const Text('Flutter + HiveVault • MIT License\n'
                'Offline-first • AES-256-GCM encrypted'),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purple.withOpacity(0.12),
              child: const Icon(Icons.info_outline,
                  color: Colors.purple, size: 20),
            ),
            title: const Text('Version'),
            subtitle: const Text('1.0.0 — Build 2026.04'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('InventoryVault',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text('v1.0.0 • Powered by HiveVault',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.lock, size: 12, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('AES-256-GCM encrypted',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey.shade600,
          ),
        ),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.12),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.primaryColor,
      );

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );

  // ── Actions ───────────────────────────────────────────────────────────────

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Currency',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _currencies
                    .map((c) => ListTile(
                          title: Text(c),
                          trailing: c == _currency
                              ? const Icon(Icons.check,
                                  color: AppTheme.primaryColor)
                              : null,
                          onTap: () {
                            setState(() => _currency = c);
                            Navigator.pop(context);
                          },
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDemoData() async {
    final prov = context.read<InventoryProvider>();
    await prov.seedDemoData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demo data loaded successfully!')));
    }
  }

  Future<void> _runAlertScan() async {
    final prov = context.read<InventoryProvider>();
    final count = await prov.runAlertScan();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alert scan: $count new alert(s)')));
    }
  }

  Future<void> _createReorderRequests() async {
    final prov = context.read<InventoryProvider>();
    final count = await prov.createReorderRequests();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count reorder request(s) created')));
    }
  }

  Future<void> _exportBackup() async {
    // Show info dialog — actual export would require a file picker package
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export Backup'),
        content: const Text(
          'All data is encrypted with AES-256-GCM and stored securely in Hive.\n\n'
          'To back up your data, copy the Hive files from:\n'
          'Android: /data/data/<app>/files/\n'
          'iOS: Application Support/\n\n'
          'Full cloud backup export coming in v1.1.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _importBackup() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: const Text(
          'To restore, place your Hive backup files in the app data directory '
          'and restart the app.\n\n'
          'Full import/export UI coming in v1.1.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _handlePinToggle(bool enable) async {
    if (enable) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AuthScreen(
            mode: AuthMode.setup,
            onSuccess: () {
              Navigator.pop(context);
              setState(() => _pinEnabled = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN set successfully!')),
              );
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Disable PIN?'),
          content: const Text('Remove PIN protection from the app?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Disable')),
          ],
        ),
      );
      if (confirmed == true) {
        await AuthService.instance.clearPin();
        setState(() => _pinEnabled = false);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('PIN removed')));
        }
      }
    }
  }

  Future<void> _changePin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          mode: AuthMode.change,
          onSuccess: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN changed successfully!')),
            );
          },
          onCancel: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
            'This will permanently delete all products, stock movements, '
            'alerts, and purchase orders. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final prov = context.read<InventoryProvider>();
      await prov.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('All data cleared')));
      }
    }
  }

  /// Opens the Audit Log viewer with entries from the products vault.
  Future<void> _showAuditLog(BuildContext ctx) async {
    VaultStats? stats;
    try {
      stats = await VaultService().getCombinedStats();
    } catch (_) {}
    if (!ctx.mounted) return;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: AppTheme.infoColor, size: 22),
            SizedBox(width: 8),
            Text('Vault Statistics'),
          ],
        ),
        content: stats == null
            ? const Text('Could not load vault statistics.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _auditRow('Box', stats.boxName),
                    _auditRow('Total Entries', '${stats.totalEntries}'),
                    _auditRow('Total Reads', '${stats.totalReads}'),
                    _auditRow('Total Writes', '${stats.totalWrites}'),
                    _auditRow('Total Searches', '${stats.totalSearches}'),
                    _auditRow('Cache Hit Rate',
                        '${(stats.cacheHitRatio * 100).toStringAsFixed(1)}%'),
                    _auditRow(
                        'Cache', '${stats.cacheSize}/${stats.cacheCapacity}'),
                    _auditRow('Compression',
                        '${stats.compressionAlgorithm} (${stats.compressionRatioLabel} saved)'),
                    _auditRow('Encryption', stats.encryptionAlgorithm),
                    _auditRow('Uptime', '${stats.uptime.inSeconds}s'),
                    const Divider(height: 16),
                    Text(
                      'Full audit trail is encrypted inside HiveVault.\n'
                      'Export a backup to inspect all records.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _auditRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );
}
