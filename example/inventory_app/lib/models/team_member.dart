// example/inventory_app/lib/models/team_member.dart
// ─────────────────────────────────────────────────────────────────────────────
// Team member / user model for the InventoryVault app.
// Supports multi-user role-based access control (RBAC).
// ─────────────────────────────────────────────────────────────────────────────

/// Roles in the inventory system.
enum UserRole {
  admin,       // Full access — all CRUD + reports + settings
  manager,     // View + edit products, orders, stock movements; no settings
  operator,    // Stock movements and scanning only
  viewer,      // Read-only access
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Administrator',
        UserRole.manager => 'Manager',
        UserRole.operator => 'Operator',
        UserRole.viewer => 'Viewer',
      };

  String get description => switch (this) {
        UserRole.admin => 'Full access to all features and settings',
        UserRole.manager => 'Manage inventory, orders, and generate reports',
        UserRole.operator => 'Record stock movements and scan barcodes',
        UserRole.viewer => 'View-only access to inventory data',
      };

  bool get canEdit => this == UserRole.admin || this == UserRole.manager;
  bool get canManageStock => this != UserRole.viewer;
  bool get canViewReports =>
      this == UserRole.admin || this == UserRole.manager;
  bool get canAccessSettings => this == UserRole.admin;
}

class TeamMember {
  final String id;
  String name;
  String email;
  UserRole role;
  bool isActive;
  String? phone;
  String? avatarInitials;
  DateTime createdAt;
  DateTime? lastActiveAt;
  String? notes;

  TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.phone,
    this.notes,
    DateTime? createdAt,
    this.lastActiveAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        avatarInitials = _initials(name);

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.index,
        'isActive': isActive,
        'phone': phone,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt?.toIso8601String(),
      };

  factory TeamMember.fromMap(Map<String, dynamic> map) => TeamMember(
        id: map['id'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        role: UserRole.values[map['role'] as int? ?? 0],
        isActive: map['isActive'] as bool? ?? true,
        phone: map['phone'] as String?,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        lastActiveAt: map['lastActiveAt'] != null
            ? DateTime.parse(map['lastActiveAt'] as String)
            : null,
      );

  TeamMember copyWith({
    String? name,
    String? email,
    UserRole? role,
    bool? isActive,
    String? phone,
    String? notes,
    DateTime? lastActiveAt,
  }) =>
      TeamMember(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
        isActive: isActive ?? this.isActive,
        phone: phone ?? this.phone,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      );
}
