// example/inventory_app/lib/screens/orders/purchase_order_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/purchase_order.dart';
import '../../providers/inventory_provider.dart';
import '../../services/pdf_service.dart';
import '../../utils/formatters.dart';
import '../../theme/app_theme.dart';

class PurchaseOrderDetailScreen extends StatelessWidget {
  final PurchaseOrder order;

  const PurchaseOrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, prov, _) {
        // Get fresh order
        final current =
            prov.orders.where((o) => o.id == order.id).firstOrNull ?? order;

        return Scaffold(
          appBar: AppBar(
            title: Text(current.orderNumber),
            actions: [
              IconButton(
                icon: const Icon(Icons.print_outlined),
                onPressed: () => PdfService.printPurchaseOrder(current),
                tooltip: 'Print PDF',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, current),
                const SizedBox(height: 12),
                _buildLines(context, current),
                const SizedBox(height: 12),
                _buildTotals(context, current),
                const SizedBox(height: 12),
                _buildActions(context, current, prov),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, PurchaseOrder order) {
    final statusColor = _statusColor(order.status);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.orderNumber,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    order.status.label,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _row('Supplier', order.supplierName),
            _row('Order Date', formatDate(order.orderDate)),
            if (order.expectedDelivery != null)
              _row('Expected Delivery', formatDate(order.expectedDelivery!)),
            if (order.receivedDate != null)
              _row('Received Date', formatDate(order.receivedDate!)),
            if (order.createdBy != null) _row('Created By', order.createdBy!),
            if (order.approvedBy != null)
              _row('Approved By', order.approvedBy!),
            if (order.notes != null && order.notes!.isNotEmpty)
              _row('Notes', order.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildLines(BuildContext context, PurchaseOrder order) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Lines',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...order.lines.map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.productName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              'SKU: ${line.sku}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Ordered: ${line.orderedQty.toInt()}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Received: ${line.receivedQty.toInt()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: line.isFullyReceived
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            formatCurrency(line.lineTotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(BuildContext context, PurchaseOrder order) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Amount',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              formatCurrency(order.totalAmount),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
      BuildContext context, PurchaseOrder order, InventoryProvider prov) {
    return Column(
      children: [
        if (order.status == PurchaseOrderStatus.draft)
          _actionBtn(
            context,
            'Submit Order',
            Icons.send,
            Colors.orange,
            () => _updateStatus(
                context, prov, order, PurchaseOrderStatus.submitted),
          ),
        if (order.canBeApproved)
          _actionBtn(
            context,
            'Approve Order',
            Icons.check_circle_outline,
            Colors.blue,
            () => _updateStatus(
                context, prov, order, PurchaseOrderStatus.approved),
          ),
        if (order.canBeSent)
          _actionBtn(
            context,
            'Mark as Sent to Supplier',
            Icons.local_shipping_outlined,
            AppTheme.primaryColor,
            () => _updateStatus(context, prov, order, PurchaseOrderStatus.sent),
          ),
        if (order.canReceive)
          _actionBtn(
            context,
            'Record Goods Receipt',
            Icons.inventory_outlined,
            Colors.green,
            () => _showReceiveDialog(context, prov, order),
          ),
        if (order.status != PurchaseOrderStatus.cancelled &&
            order.status != PurchaseOrderStatus.fullyReceived)
          _actionBtn(
            context,
            'Cancel Order',
            Icons.cancel_outlined,
            Colors.red,
            () => _updateStatus(
                context, prov, order, PurchaseOrderStatus.cancelled),
            outlined: true,
          ),
      ],
    );
  }

  Widget _actionBtn(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    bool outlined = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: outlined
              ? OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, color: color),
                  label: Text(label, style: TextStyle(color: color)),
                  style:
                      OutlinedButton.styleFrom(side: BorderSide(color: color)),
                )
              : ElevatedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                  style: ElevatedButton.styleFrom(backgroundColor: color),
                ),
        ),
      );

  Future<void> _updateStatus(
    BuildContext context,
    InventoryProvider prov,
    PurchaseOrder order,
    PurchaseOrderStatus status,
  ) async {
    await prov.updateOrderStatus(order.id, status);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Order status updated to: ${status.label}')),
    );
  }

  void _showReceiveDialog(
      BuildContext context, InventoryProvider prov, PurchaseOrder order) {
    final quantities = <String, TextEditingController>{
      for (final line in order.lines)
        line.productId:
            TextEditingController(text: line.pendingQty.toStringAsFixed(0))
    };

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Record Goods Receipt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: order.lines.map((line) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.productName}\n(Pending: ${line.pendingQty.toInt()})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: quantities[line.productId],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final received = {
                for (final entry in quantities.entries)
                  entry.key: double.tryParse(entry.value.text) ?? 0,
              };
              Navigator.pop(context);
              await prov.receiveOrder(order, received);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Goods receipt recorded!')),
              );
            },
            child: const Text('Confirm Receipt'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Color _statusColor(PurchaseOrderStatus status) => switch (status) {
        PurchaseOrderStatus.draft => Colors.grey,
        PurchaseOrderStatus.submitted => Colors.orange,
        PurchaseOrderStatus.approved => Colors.blue,
        PurchaseOrderStatus.sent => AppTheme.primaryColor,
        PurchaseOrderStatus.partiallyReceived => Colors.amber,
        PurchaseOrderStatus.fullyReceived => Colors.green,
        PurchaseOrderStatus.cancelled => Colors.red,
      };
}
