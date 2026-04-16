// example/inventory_app/lib/services/pdf_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// PDF generation for inventory reports and purchase orders.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/inventory_report.dart';
import '../models/purchase_order.dart';
import '../models/stock_movement.dart';

final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _dateFormat = DateFormat('dd MMM yyyy HH:mm');

class PdfService {
  /// Print a low-stock report as PDF.
  static Future<void> printLowStockReport(List<LowStockItem> items) async {
    final doc = pw.Document();
    doc.addPage(_buildLowStockPage(items));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  /// Print a valuation report as PDF.
  static Future<void> printValuationReport(List<ValuationItem> items) async {
    final doc = pw.Document();
    doc.addPage(_buildValuationPage(items));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  /// Print a purchase order as PDF.
  static Future<void> printPurchaseOrder(PurchaseOrder order) async {
    final doc = pw.Document();
    doc.addPage(_buildPurchaseOrderPage(order));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  /// Print a stock movement report.
  static Future<void> printMovementReport(List<StockMovement> movements) async {
    final doc = pw.Document();
    doc.addPage(_buildMovementPage(movements));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ── Page builders ─────────────────────────────────────────────────────────

  static pw.Page _buildLowStockPage(List<LowStockItem> items) {
    final date = DateFormat('dd MMM yyyy').format(DateTime.now());
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Low Stock Report', date),
          pw.SizedBox(height: 16),
          pw.Text(
            '${items.length} product(s) below minimum stock threshold',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _tableHeader([
                'Product',
                'SKU',
                'Category',
                'Current',
                'Min',
                'Reorder Qty',
                'Supplier'
              ]),
              ...items.map((item) => _tableRow([
                    item.name,
                    item.sku,
                    item.categoryName,
                    item.currentStock.toStringAsFixed(0),
                    item.minimumStock.toStringAsFixed(0),
                    item.reorderQty.toStringAsFixed(0),
                    item.supplierName ?? '-',
                  ])),
            ],
          ),
          pw.SizedBox(height: 16),
          _footer(),
        ],
      ),
    );
  }

  static pw.Page _buildValuationPage(List<ValuationItem> items) {
    final date = DateFormat('dd MMM yyyy').format(DateTime.now());
    final totalCost = items.fold(0.0, (s, i) => s + i.costValue);
    final totalSell = items.fold(0.0, (s, i) => s + i.sellingValue);

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Inventory Valuation Report', date),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _tableHeader([
                'Product',
                'SKU',
                'Qty',
                'Cost Price',
                'Sell Price',
                'Cost Value',
                'Sell Value'
              ]),
              ...items.map((item) => _tableRow([
                    item.name,
                    item.sku,
                    item.quantity.toStringAsFixed(0),
                    _currency.format(item.costPrice),
                    _currency.format(item.sellingPrice),
                    _currency.format(item.costValue),
                    _currency.format(item.sellingValue),
                  ])),
              _tableRow([
                'TOTAL',
                '',
                '',
                '',
                '',
                _currency.format(totalCost),
                _currency.format(totalSell),
              ], bold: true),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            pw.Text('Gross Profit: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(_currency.format(totalSell - totalCost)),
          ]),
          pw.SizedBox(height: 8),
          _footer(),
        ],
      ),
    );
  }

  static pw.Page _buildPurchaseOrderPage(PurchaseOrder order) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Purchase Order', order.orderNumber),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Supplier: ${order.supplierName}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        'Order Date: ${DateFormat('dd MMM yyyy').format(order.orderDate)}'),
                    if (order.expectedDelivery != null)
                      pw.Text(
                          'Expected: ${DateFormat('dd MMM yyyy').format(order.expectedDelivery!)}'),
                  ]),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  order.status.label,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _tableHeader([
                'Product',
                'SKU',
                'Ordered Qty',
                'Received',
                'Unit Cost',
                'Total'
              ]),
              ...order.lines.map((line) => _tableRow([
                    line.productName,
                    line.sku,
                    line.orderedQty.toStringAsFixed(0),
                    line.receivedQty.toStringAsFixed(0),
                    _currency.format(line.unitCost),
                    _currency.format(line.lineTotal),
                  ])),
              _tableRow([
                'TOTAL',
                '',
                '',
                '',
                '',
                _currency.format(order.totalAmount),
              ], bold: true),
            ],
          ),
          if (order.notes != null) ...[
            pw.SizedBox(height: 12),
            pw.Text('Notes: ${order.notes}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
          pw.SizedBox(height: 16),
          _footer(),
        ],
      ),
    );
  }

  static pw.Page _buildMovementPage(List<StockMovement> movements) {
    final date = DateFormat('dd MMM yyyy').format(DateTime.now());
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Stock Movement Report', date),
          pw.SizedBox(height: 12),
          pw.Text('${movements.length} movement(s)',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _tableHeader(
                  ['Date', 'Type', 'Qty', 'Before', 'After', 'Reference']),
              ...movements.take(50).map((m) => _tableRow([
                    DateFormat('dd/MM/yy HH:mm').format(m.createdAt),
                    m.type.label,
                    m.quantity.toStringAsFixed(0),
                    m.stockBefore.toStringAsFixed(0),
                    m.stockAfter.toStringAsFixed(0),
                    m.reference ?? '-',
                  ])),
            ],
          ),
          pw.SizedBox(height: 16),
          _footer(),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static pw.Widget _header(String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'InventoryVault',
                style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.blue700,
                    fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Divider(),
          pw.Text(subtitle,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ],
      );

  static pw.TableRow _tableHeader(List<String> columns) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blue700),
        children: columns
            .map((c) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(c,
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9)),
                ))
            .toList(),
      );

  static pw.TableRow _tableRow(List<String> cells, {bool bold = false}) =>
      pw.TableRow(
        children: cells
            .map((c) => pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    c,
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: bold ? pw.FontWeight.bold : null),
                  ),
                ))
            .toList(),
      );

  static pw.Widget _footer() => pw.Column(children: [
        pw.Divider(),
        pw.Text(
          'Generated by InventoryVault • ${_dateFormat.format(DateTime.now())} • Powered by HiveVault',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          textAlign: pw.TextAlign.center,
        ),
      ]);
}
