// example/inventory_app/lib/models/product.dart
// ─────────────────────────────────────────────────────────────────────────────
// Product model — stored encrypted via HiveVault.
// ─────────────────────────────────────────────────────────────────────────────

/// Product status in the inventory.
enum ProductStatus { active, discontinued, draft }

/// Unit of measure for quantity tracking.
enum UnitOfMeasure { pieces, kg, liters, meters, boxes, pallets }

/// Core product entity stored and retrieved through HiveVault.
class Product {
  final String id;
  String name;
  String sku; // Stock-Keeping Unit (unique identifier)
  String barcode; // EAN-13, UPC-A, QR, etc.
  String? description;
  String categoryId;
  String? supplierId;
  String? imageUrl;

  // ── Stock ─────────────────────────────────────────────────────────────────
  double currentStock;
  double minimumStock; // Low-stock threshold
  double reorderPoint; // Triggers auto reorder request
  double reorderQty; // Suggested reorder quantity
  double maximumStock;

  // ── Pricing ───────────────────────────────────────────────────────────────
  double costPrice;
  double sellingPrice;

  // ── Metadata ─────────────────────────────────────────────────────────────
  UnitOfMeasure unit;
  ProductStatus status;
  String? location; // Warehouse location / bin code
  DateTime createdAt;
  DateTime updatedAt;
  Map<String, dynamic> customFields;

  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.categoryId,
    this.supplierId,
    this.description,
    this.imageUrl,
    this.currentStock = 0,
    this.minimumStock = 5,
    this.reorderPoint = 10,
    this.reorderQty = 50,
    this.maximumStock = 500,
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.unit = UnitOfMeasure.pieces,
    this.status = ProductStatus.active,
    this.location,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? customFields,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        customFields = customFields ?? {};

  // ── Computed properties ───────────────────────────────────────────────────

  bool get isLowStock => currentStock <= minimumStock;
  bool get needsReorder => currentStock <= reorderPoint;
  bool get isOutOfStock => currentStock <= 0;
  double get stockValue => currentStock * costPrice;
  double get margin =>
      sellingPrice > 0 ? ((sellingPrice - costPrice) / sellingPrice) * 100 : 0;

  String get stockStatusLabel {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    if (currentStock >= maximumStock) return 'Overstocked';
    return 'In Stock';
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'description': description,
        'categoryId': categoryId,
        'supplierId': supplierId,
        'imageUrl': imageUrl,
        'currentStock': currentStock,
        'minimumStock': minimumStock,
        'reorderPoint': reorderPoint,
        'reorderQty': reorderQty,
        'maximumStock': maximumStock,
        'costPrice': costPrice,
        'sellingPrice': sellingPrice,
        'unit': unit.index,
        'status': status.index,
        'location': location,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'customFields': customFields,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String,
        sku: map['sku'] as String,
        barcode: map['barcode'] as String,
        categoryId: map['categoryId'] as String,
        supplierId: map['supplierId'] as String?,
        description: map['description'] as String?,
        imageUrl: map['imageUrl'] as String?,
        currentStock: (map['currentStock'] as num).toDouble(),
        minimumStock: (map['minimumStock'] as num).toDouble(),
        reorderPoint: (map['reorderPoint'] as num).toDouble(),
        reorderQty: (map['reorderQty'] as num).toDouble(),
        maximumStock: (map['maximumStock'] as num).toDouble(),
        costPrice: (map['costPrice'] as num).toDouble(),
        sellingPrice: (map['sellingPrice'] as num).toDouble(),
        unit: UnitOfMeasure.values[(map['unit'] as int)],
        status: ProductStatus.values[(map['status'] as int)],
        location: map['location'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        customFields:
            Map<String, dynamic>.from(map['customFields'] as Map? ?? {}),
      );

  Product copyWith({
    String? name,
    String? sku,
    String? barcode,
    String? description,
    String? categoryId,
    String? supplierId,
    String? imageUrl,
    double? currentStock,
    double? minimumStock,
    double? reorderPoint,
    double? reorderQty,
    double? maximumStock,
    double? costPrice,
    double? sellingPrice,
    UnitOfMeasure? unit,
    ProductStatus? status,
    String? location,
    Map<String, dynamic>? customFields,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      currentStock: currentStock ?? this.currentStock,
      minimumStock: minimumStock ?? this.minimumStock,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      reorderQty: reorderQty ?? this.reorderQty,
      maximumStock: maximumStock ?? this.maximumStock,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      unit: unit ?? this.unit,
      status: status ?? this.status,
      location: location ?? this.location,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      customFields: customFields ?? this.customFields,
    );
  }

  @override
  String toString() =>
      'Product($name, SKU:$sku, Stock:$currentStock ${unit.name})';
}
