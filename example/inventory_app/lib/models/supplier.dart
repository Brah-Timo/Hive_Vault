// example/inventory_app/lib/models/supplier.dart

class Supplier {
  final String id;
  String name;
  String? contactName;
  String? email;
  String? phone;
  String? address;
  String? website;
  String? taxNumber;
  double defaultLeadTimeDays;
  double rating; // 0-5
  bool isActive;
  String? notes;
  DateTime createdAt;

  Supplier({
    required this.id,
    required this.name,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.taxNumber,
    this.defaultLeadTimeDays = 7,
    this.rating = 0,
    this.isActive = true,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'contactName': contactName,
        'email': email,
        'phone': phone,
        'address': address,
        'website': website,
        'taxNumber': taxNumber,
        'defaultLeadTimeDays': defaultLeadTimeDays,
        'rating': rating,
        'isActive': isActive,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
        id: map['id'] as String,
        name: map['name'] as String,
        contactName: map['contactName'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        address: map['address'] as String?,
        website: map['website'] as String?,
        taxNumber: map['taxNumber'] as String?,
        defaultLeadTimeDays:
            (map['defaultLeadTimeDays'] as num?)?.toDouble() ?? 7,
        rating: (map['rating'] as num?)?.toDouble() ?? 0,
        isActive: map['isActive'] as bool? ?? true,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  Supplier copyWith({
    String? name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? website,
    String? taxNumber,
    double? defaultLeadTimeDays,
    double? rating,
    bool? isActive,
    String? notes,
  }) =>
      Supplier(
        id: id,
        name: name ?? this.name,
        contactName: contactName ?? this.contactName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        website: website ?? this.website,
        taxNumber: taxNumber ?? this.taxNumber,
        defaultLeadTimeDays: defaultLeadTimeDays ?? this.defaultLeadTimeDays,
        rating: rating ?? this.rating,
        isActive: isActive ?? this.isActive,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );
}
