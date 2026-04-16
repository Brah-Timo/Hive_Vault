// example/inventory_app/lib/models/stock_alert.dart

enum AlertType {
  lowStock,
  outOfStock,
  overStock,
  expiryWarning,
  reorderRequired,
}

enum AlertSeverity { info, warning, critical }

extension AlertSeverityX on AlertSeverity {
  String get label => switch (this) {
        AlertSeverity.info => 'Info',
        AlertSeverity.warning => 'Warning',
        AlertSeverity.critical => 'Critical',
      };
}

class StockAlert {
  final String id;
  final String productId;
  final String productName;
  final AlertType type;
  final AlertSeverity severity;
  final String message;
  final double? currentStock;
  final double? threshold;
  bool isRead;
  bool isDismissed;
  DateTime createdAt;
  DateTime? readAt;

  StockAlert({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.severity,
    required this.message,
    this.currentStock,
    this.threshold,
    this.isRead = false,
    this.isDismissed = false,
    DateTime? createdAt,
    this.readAt,
  }) : createdAt = createdAt ?? DateTime.now();

  void markRead() {
    isRead = true;
    readAt = DateTime.now();
  }

  void dismiss() => isDismissed = true;

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'type': type.index,
        'severity': severity.index,
        'message': message,
        'currentStock': currentStock,
        'threshold': threshold,
        'isRead': isRead,
        'isDismissed': isDismissed,
        'createdAt': createdAt.toIso8601String(),
        'readAt': readAt?.toIso8601String(),
      };

  factory StockAlert.fromMap(Map<String, dynamic> map) => StockAlert(
        id: map['id'] as String,
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        type: AlertType.values[map['type'] as int],
        severity: AlertSeverity.values[map['severity'] as int],
        message: map['message'] as String,
        currentStock: (map['currentStock'] as num?)?.toDouble(),
        threshold: (map['threshold'] as num?)?.toDouble(),
        isRead: map['isRead'] as bool? ?? false,
        isDismissed: map['isDismissed'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        readAt: map['readAt'] != null
            ? DateTime.parse(map['readAt'] as String)
            : null,
      );
}
