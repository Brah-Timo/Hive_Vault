// example/inventory_app/lib/utils/formatters.dart

import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _dateShort = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy HH:mm');
final _timeAgo = DateFormat('HH:mm');
final _number = NumberFormat('#,##0.##');

String formatCurrency(double amount) => _currency.format(amount);

String formatDate(DateTime date) => _dateShort.format(date);

String formatDateTime(DateTime date) => _dateTime.format(date);

String formatNumber(double value) => _number.format(value);

String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

String timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return _dateShort.format(date);
}

String formatStock(double stock, String unitName) {
  if (stock == stock.roundToDouble()) {
    return '${stock.toInt()} $unitName';
  }
  return '${stock.toStringAsFixed(1)} $unitName';
}
