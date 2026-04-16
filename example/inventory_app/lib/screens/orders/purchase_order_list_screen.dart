// example/inventory_app/lib/screens/orders/purchase_order_list_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Purchase Orders list — with status filter, summary bar, and auto-reorder.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_order.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/empty_state.dart';
import '../../utils/formatters.dart';
import '../../theme/app_theme.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_form_screen.dart';

class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() =>
      _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  PurchaseOrderStatus? _statusFilter;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        var orders = List<PurchaseOrder>.from(prov.orders);

        // Apply filters
        if (_statusFilter != null) {
          orders = orders
              .where((o) => o.status == _statusFilter)
              .toList();
        }
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          orders = orders
              .where((o) =>
                  o.orderNumber.toLowerCase().contains(q) ||
                  o.supplierName.toLowerCase().contains(q) ||
                  (o.notes?.toLowerCase().contains(q) ?? false))
              .toList();
        }
        orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Purchase Orders'),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter by status',
                onPressed: () => _showStatusFilter(context),
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'Create Reorder Requests',
                onPressed: () async {
                  final count = await prov.createReorderRequests();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text('$count reorder request(s) created'),
                  ));
                },
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchBar(),
              _buildStatusFilterChips(prov.orders),
              _buildSummaryBar(context, prov.orders),
              Expanded(
                child: orders.isEmpty
                    ? EmptyState(
                        icon: Icons.shopping_cart_outlined,
                        title: 'No Purchase Orders',
                        subtitle: _statusFilter != null || _search.isNotEmpty
                            ? 'No orders match your filter.'
                            : 'Create your first purchase order to get started',
                        action: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const PurchaseOrderFormScreen()),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Order'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: prov.loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            return _OrderCard(
                              order: order,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PurchaseOrderDetailScreen(
                                          order: order),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PurchaseOrderFormScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('New Order'),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Search by order number, supplier…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    })
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      );

  Widget _buildStatusFilterChips(List<PurchaseOrder> allOrders) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          _statusChip(null, 'All (${allOrders.length})'),
          ...PurchaseOrderStatus.values.map((s) {
            final count =
                allOrders.where((o) => o.status == s).length;
            return _statusChip(s, '${s.label} ($count)');
          }),
        ],
      ),
    );
  }

  Widget _statusChip(PurchaseOrderStatus? status, String label) {
    final isSelected = _statusFilter == status;
    final color = status == null
        ? AppTheme.primaryColor
        : _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w500)),
        selected: isSelected,
        onSelected: (_) =>
            setState(() => _statusFilter = status),
        backgroundColor: color.withOpacity(0.08),
        selectedColor: color,
        checkmarkColor: Colors.white,
        side: BorderSide(
            color: color.withOpacity(isSelected ? 1 : 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSummaryBar(
      BuildContext context, List<PurchaseOrder> all) {
    final pending = all
        .where((o) =>
            o.status != PurchaseOrderStatus.fullyReceived &&
            o.status != PurchaseOrderStatus.cancelled)
        .length;
    final total = all.fold(0.0, (s, o) => s + o.totalAmount);

    return Container(
      color: AppTheme.primaryColor.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('${all.length}', 'Total'),
          _stat('$pending', 'Pending'),
          _stat(formatCurrency(total), 'Value'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  void _showStatusFilter(BuildContext context) {
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
                    borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Filter by Status',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('All Statuses'),
              trailing: _statusFilter == null
                  ? const Icon(Icons.check,
                      color: AppTheme.primaryColor)
                  : null,
              onTap: () {
                setState(() => _statusFilter = null);
                Navigator.pop(context);
              },
            ),
            ...PurchaseOrderStatus.values.map((s) => ListTile(
                  leading: Icon(Icons.circle, color: _statusColor(s), size: 14),
                  title: Text(s.label),
                  trailing: _statusFilter == s
                      ? const Icon(Icons.check,
                          color: AppTheme.primaryColor)
                      : null,
                  onTap: () {
                    setState(() => _statusFilter = s);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Color _statusColor(PurchaseOrderStatus s) => switch (s) {
        PurchaseOrderStatus.draft => Colors.grey,
        PurchaseOrderStatus.submitted => Colors.orange,
        PurchaseOrderStatus.approved => Colors.blue,
        PurchaseOrderStatus.sent => AppTheme.primaryColor,
        PurchaseOrderStatus.partiallyReceived => Colors.amber,
        PurchaseOrderStatus.fullyReceived => Colors.green,
        PurchaseOrderStatus.cancelled => Colors.red,
      };
}

// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final PurchaseOrder order;
  final VoidCallback? onTap;
  const _OrderCard({required this.order, this.onTap});

  Color get _statusColor => switch (order.status) {
        PurchaseOrderStatus.draft => Colors.grey,
        PurchaseOrderStatus.submitted => Colors.orange,
        PurchaseOrderStatus.approved => Colors.blue,
        PurchaseOrderStatus.sent => AppTheme.primaryColor,
        PurchaseOrderStatus.partiallyReceived => Colors.amber,
        PurchaseOrderStatus.fullyReceived => Colors.green,
        PurchaseOrderStatus.cancelled => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.orderNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(order.supplierName,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    order.status.label,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _info('${order.totalItems} item(s)',
                      Icons.inventory_outlined),
                  _info(formatCurrency(order.totalAmount),
                      Icons.attach_money),
                  _info(
                    DateFormat('dd MMM yy').format(order.orderDate),
                    Icons.calendar_today_outlined,
                  ),
                  if (order.expectedDelivery != null)
                    _info(
                      'ETA: ${DateFormat('dd MMM').format(order.expectedDelivery!)}',
                      Icons.local_shipping_outlined,
                    ),
                ],
              ),
              // Progress bar for partially received
              if (order.status ==
                  PurchaseOrderStatus.partiallyReceived) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: order.receivedProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.amber),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(order.receivedProgress * 100).toInt()}% received',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String text, IconData icon) => Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
}
