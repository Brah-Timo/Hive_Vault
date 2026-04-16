// example/inventory_app/lib/models/purchase_order.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reorder / Purchase Order model.
// ─────────────────────────────────────────────────────────────────────────────

enum PurchaseOrderStatus {
  draft,
  submitted,
  approved,
  sent, // Sent to supplier
  partiallyReceived,
  fullyReceived,
  cancelled,
}

extension POStatusX on PurchaseOrderStatus {
  String get label => switch (this) {
        PurchaseOrderStatus.draft => 'Draft',
        PurchaseOrderStatus.submitted => 'Submitted',
        PurchaseOrderStatus.approved => 'Approved',
        PurchaseOrderStatus.sent => 'Sent to Supplier',
        PurchaseOrderStatus.partiallyReceived => 'Partially Received',
        PurchaseOrderStatus.fullyReceived => 'Fully Received',
        PurchaseOrderStatus.cancelled => 'Cancelled',
      };
}

class PurchaseOrderLine {
  final String productId;
  final String productName;
  final String sku;
  double orderedQty;
  double receivedQty;
  double unitCost;
  String? notes;

  PurchaseOrderLine({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.orderedQty,
    this.receivedQty = 0,
    required this.unitCost,
    this.notes,
  });

  double get lineTotal => orderedQty * unitCost;
  double get pendingQty => orderedQty - receivedQty;
  bool get isFullyReceived => receivedQty >= orderedQty;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'orderedQty': orderedQty,
        'receivedQty': receivedQty,
        'unitCost': unitCost,
        'notes': notes,
      };

  factory PurchaseOrderLine.fromMap(Map<String, dynamic> map) =>
      PurchaseOrderLine(
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        sku: map['sku'] as String,
        orderedQty: (map['orderedQty'] as num).toDouble(),
        receivedQty: (map['receivedQty'] as num?)?.toDouble() ?? 0,
        unitCost: (map['unitCost'] as num).toDouble(),
        notes: map['notes'] as String?,
      );
}

class PurchaseOrder {
  final String id;
  String orderNumber;
  String supplierId;
  String supplierName;
  List<PurchaseOrderLine> lines;
  PurchaseOrderStatus status;
  DateTime orderDate;
  DateTime? expectedDelivery;
  DateTime? receivedDate;
  String? notes;
  String? createdBy;
  String? approvedBy;
  DateTime createdAt;
  DateTime updatedAt;

  PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.lines,
    this.status = PurchaseOrderStatus.draft,
    DateTime? orderDate,
    this.expectedDelivery,
    this.receivedDate,
    this.notes,
    this.createdBy,
    this.approvedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : orderDate = orderDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get totalAmount => lines.fold(0, (sum, l) => sum + l.lineTotal);

  int get totalItems => lines.length;

  /// Progress of received items (0.0–1.0).
  double get receivedProgress {
    if (lines.isEmpty) return 0.0;
    final totalOrdered = lines.fold(0.0, (s, l) => s + l.orderedQty);
    if (totalOrdered == 0) return 0.0;
    final totalReceived = lines.fold(0.0, (s, l) => s + l.receivedQty);
    return (totalReceived / totalOrdered).clamp(0.0, 1.0);
  }

  bool get canBeApproved => status == PurchaseOrderStatus.submitted;
  bool get canBeSent => status == PurchaseOrderStatus.approved;
  bool get canReceive =>
      status == PurchaseOrderStatus.sent ||
      status == PurchaseOrderStatus.partiallyReceived;

  Map<String, dynamic> toMap() => {
        'id': id,
        'orderNumber': orderNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'lines': lines.map((l) => l.toMap()).toList(),
        'status': status.index,
        'orderDate': orderDate.toIso8601String(),
        'expectedDelivery': expectedDelivery?.toIso8601String(),
        'receivedDate': receivedDate?.toIso8601String(),
        'notes': notes,
        'createdBy': createdBy,
        'approvedBy': approvedBy,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) => PurchaseOrder(
        id: map['id'] as String,
        orderNumber: map['orderNumber'] as String,
        supplierId: map['supplierId'] as String,
        supplierName: map['supplierName'] as String,
        lines: (map['lines'] as List)
            .map((l) => PurchaseOrderLine.fromMap(l as Map<String, dynamic>))
            .toList(),
        status: PurchaseOrderStatus.values[map['status'] as int],
        orderDate: DateTime.parse(map['orderDate'] as String),
        expectedDelivery: map['expectedDelivery'] != null
            ? DateTime.parse(map['expectedDelivery'] as String)
            : null,
        receivedDate: map['receivedDate'] != null
            ? DateTime.parse(map['receivedDate'] as String)
            : null,
        notes: map['notes'] as String?,
        createdBy: map['createdBy'] as String?,
        approvedBy: map['approvedBy'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );

  PurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    List<PurchaseOrderLine>? lines,
    DateTime? expectedDelivery,
    DateTime? receivedDate,
    String? notes,
    String? approvedBy,
  }) =>
      PurchaseOrder(
        id: id,
        orderNumber: orderNumber,
        supplierId: supplierId,
        supplierName: supplierName,
        lines: lines ?? this.lines,
        status: status ?? this.status,
        orderDate: orderDate,
        expectedDelivery: expectedDelivery ?? this.expectedDelivery,
        receivedDate: receivedDate ?? this.receivedDate,
        notes: notes ?? this.notes,
        createdBy: createdBy,
        approvedBy: approvedBy ?? this.approvedBy,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
