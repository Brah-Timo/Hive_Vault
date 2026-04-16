// example/inventory_app/lib/screens/audit/audit_log_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Audit Log Viewer — displays HiveVault encrypted audit trail.
// Shows all read/write/delete operations with timestamps and user IDs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

/// Represents a single audit log entry for display.
class AuditLogEntry {
  final String operation; // read, write, delete, etc.
  final String key;
  final DateTime timestamp;
  final String? userId;
  final Map<String, dynamic>? metadata;

  const AuditLogEntry({
    required this.operation,
    required this.key,
    required this.timestamp,
    this.userId,
    this.metadata,
  });
}

class AuditLogScreen extends StatefulWidget {
  final List<AuditLogEntry> entries;
  final String title;

  const AuditLogScreen({
    super.key,
    required this.entries,
    this.title = 'Audit Log',
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _opFilter = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AuditLogEntry> get _filtered {
    var list = widget.entries;
    if (_opFilter != 'all') {
      list = list.where((e) => e.operation == _opFilter).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) =>
              e.key.toLowerCase().contains(q) ||
              (e.userId?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter by operation',
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by key or user…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Operation filter chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: ['all', 'write', 'read', 'delete']
                  .map((op) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(op == 'all' ? 'All' : op.capitalize()),
                          selected: _opFilter == op,
                          onSelected: (_) => setState(() => _opFilter = op),
                          backgroundColor: Colors.grey.shade100,
                          selectedColor:
                              AppTheme.primaryColor.withOpacity(0.15),
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Stats bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${entries.length} entries',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (_opFilter != 'all' || _search.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _opFilter = 'all';
                        _search = '';
                      });
                    },
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ),
          // List
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          widget.entries.isEmpty
                              ? 'No audit entries found'
                              : 'No entries match filter',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Filter by Operation',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...['all', 'write', 'read', 'delete'].map((op) => ListTile(
                  leading: Icon(
                    _opIcon(op),
                    color: _opColor(op),
                  ),
                  title: Text(op == 'all' ? 'All Operations' : op.capitalize()),
                  trailing: _opFilter == op ? const Icon(Icons.check) : null,
                  onTap: () {
                    setState(() => _opFilter = op);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _opIcon(String op) => switch (op) {
        'write' => Icons.edit_outlined,
        'read' => Icons.visibility_outlined,
        'delete' => Icons.delete_outline,
        _ => Icons.history_outlined,
      };

  Color _opColor(String op) => switch (op) {
        'write' => AppTheme.primaryColor,
        'read' => AppTheme.infoColor,
        'delete' => AppTheme.errorColor,
        _ => Colors.grey,
      };
}

class _EntryTile extends StatelessWidget {
  final AuditLogEntry entry;
  const _EntryTile({required this.entry});

  Color get _color => switch (entry.operation) {
        'write' => AppTheme.primaryColor,
        'read' => AppTheme.infoColor,
        'delete' => AppTheme.errorColor,
        _ => Colors.grey,
      };

  IconData get _icon => switch (entry.operation) {
        'write' => Icons.edit_outlined,
        'read' => Icons.visibility_outlined,
        'delete' => Icons.delete_outline,
        _ => Icons.history_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM HH:mm:ss');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _color.withOpacity(0.12),
          child: Icon(_icon, size: 14, color: _color),
        ),
        title: Text(
          entry.key,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              entry.operation.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: _color,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (entry.userId != null) ...[
              const SizedBox(width: 6),
              Text(
                '• ${entry.userId}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ],
        ),
        trailing: Text(
          df.format(entry.timestamp),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
    );
  }
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
