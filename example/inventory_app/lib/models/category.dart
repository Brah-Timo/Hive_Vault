// example/inventory_app/lib/models/category.dart
// ─────────────────────────────────────────────────────────────────────────────
// ProductCategory model — renamed from "Category" to avoid conflict with
// Flutter's internal foundation.Category annotation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Represents a product category in the inventory system.
///
/// Named [ProductCategory] (not [Category]) to avoid ambiguity with
/// Flutter's `@Category` annotation from `package:flutter/foundation.dart`.
class ProductCategory {
  final String id;
  String name;
  String? description;
  String? parentId; // For sub-categories
  int colorValue; // Flutter Color.value
  String iconName; // Material icon name
  bool isActive;
  DateTime createdAt;

  ProductCategory({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    this.colorValue = 0xFF2196F3,
    this.iconName = 'category',
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convenience getter — returns the Flutter [Color] for this category.
  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'parentId': parentId,
        'colorValue': colorValue,
        'iconName': iconName,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ProductCategory.fromMap(Map<String, dynamic> map) => ProductCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        parentId: map['parentId'] as String?,
        colorValue: map['colorValue'] as int? ?? 0xFF2196F3,
        iconName: map['iconName'] as String? ?? 'category',
        isActive: map['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  ProductCategory copyWith({
    String? name,
    String? description,
    String? parentId,
    int? colorValue,
    String? iconName,
    bool? isActive,
  }) =>
      ProductCategory(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        parentId: parentId ?? this.parentId,
        colorValue: colorValue ?? this.colorValue,
        iconName: iconName ?? this.iconName,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}

/// Pre-defined default categories for quick setup.
final kDefaultCategories = [
  ProductCategory(
      id: 'cat_electronics',
      name: 'Electronics',
      colorValue: 0xFF1565C0,
      iconName: 'devices'),
  ProductCategory(
      id: 'cat_clothing',
      name: 'Clothing',
      colorValue: 0xFF6A1B9A,
      iconName: 'checkroom'),
  ProductCategory(
      id: 'cat_food',
      name: 'Food & Beverages',
      colorValue: 0xFF2E7D32,
      iconName: 'restaurant'),
  ProductCategory(
      id: 'cat_office',
      name: 'Office Supplies',
      colorValue: 0xFF4E342E,
      iconName: 'business_center'),
  ProductCategory(
      id: 'cat_hardware',
      name: 'Hardware & Tools',
      colorValue: 0xFFE65100,
      iconName: 'hardware'),
  ProductCategory(
      id: 'cat_health',
      name: 'Health & Beauty',
      colorValue: 0xFFD81B60,
      iconName: 'local_pharmacy'),
];
