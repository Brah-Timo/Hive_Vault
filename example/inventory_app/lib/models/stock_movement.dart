// example/inventory_app/lib/models/stock_movement.dart
// ─────────────────────────────────────────────────────────────────────────────
// Records every change in inventory quantity.
// ─────────────────────────────────────────────────────────────────────────────

/// Type of stock movement.
enum MovementType {
  stockIn,       // Goods received
  stockOut,      // Goods dispatched / sold
  adjustment,    // Manual inventory correction
  transfer,      // Between locations
  returnIn,      // Customer return
  returnOut,     // Return to supplier
  damaged,       // Write-off for damaged goods
  expired,       // Write-off for expired goods
}

extension MovementTypeX on MovementType {
  String get label => switch (this) {
        MovementType.stockIn => 'Stock In',
        MovementType.stockOut => 'Stock Out',
        MovementType.adjustment => 'Adjustment',
        MovementType.transfer => 'Transfer',
        MovementType.returnIn => 'Return In',
        MovementType.returnOut => 'Return Out',
        MovementType.damaged => 'Damaged',
        MovementType.expired => 'Expired',
      };

  bool get isPositive =>
      this == MovementType.stockIn ||
      this == MovementType.returnIn;
}

class StockMovement {
  final String id;
  final String productId;
  final MovementType type;
  final double quantity;       // Always positive; direction inferred from type
  final double stockBefore;
  final double stockAfter;
  final String? reference;     // PO number, invoice, etc.
  final String? notes;
  final String? userId;        // Who performed the movement
  final String? locationFrom;
  final String? locationTo;
  final String? orderId;       // Related purchase/sales order
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  StockMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.reference,
    this.notes,
    this.userId,
    this.locationFrom,
    this.locationTo,
    this.orderId,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  })  : createdAt = createdAt ?? DateTime.now(),
        metadata = metadata ?? {};

  double get delta => type.isPositive ? quantity : -quantity;

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'type': type.index,
        'quantity': quantity,
        'stockBefore': stockBefore,
        'stockAfter': stockAfter,
        'reference': reference,
        'notes': notes,
        'userId': userId,
        'locationFrom': locationFrom,
        'locationTo': locationTo,
        'orderId': orderId,
        'createdAt': createdAt.toIso8601String(),
        'metadata': metadata,
      };

  factory StockMovement.fromMap(Map<String, dynamic> map) => StockMovement(
        id: map['id'] as String,
        productId: map['productId'] as String,
        type: MovementType.values[map['type'] as int],
        quantity: (map['quantity'] as num).toDouble(),
        stockBefore: (map['stockBefore'] as num).toDouble(),
        stockAfter: (map['stockAfter'] as num).toDouble(),
        reference: map['reference'] as String?,
        notes: map['notes'] as String?,
        userId: map['userId'] as String?,
        locationFrom: map['locationFrom'] as String?,
        locationTo: map['locationTo'] as String?,
        orderId: map['orderId'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      );
}
