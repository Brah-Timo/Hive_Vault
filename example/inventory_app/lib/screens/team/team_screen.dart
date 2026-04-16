// example/inventory_app/lib/screens/team/team_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Team Management screen — add/edit/deactivate team members with RBAC roles.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/team_member.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  // In-memory team list (persist to settings vault in full implementation)
  final List<TeamMember> _members = [
    TeamMember(
      id: 'admin_1',
      name: 'System Admin',
      email: 'admin@inventoryvault.com',
      role: UserRole.admin,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final active = _members.where((m) => m.isActive).toList();
    final inactive = _members.where((m) => !m.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add team member',
            onPressed: () => _showForm(context),
          ),
        ],
      ),
      body: _members.isEmpty
          ? EmptyState(
              icon: Icons.group_outlined,
              title: 'No Team Members',
              subtitle: 'Add your first team member to get started',
              action: ElevatedButton.icon(
                onPressed: () => _showForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Member'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              children: [
                if (active.isNotEmpty) ...[
                  _sectionLabel('Active Members (${active.length})'),
                  ...active.map((m) => _MemberCard(
                        member: m,
                        onEdit: () => _showForm(context, existing: m),
                        onToggleActive: () => _toggleActive(m),
                        onDelete: () => _confirmDelete(context, m),
                      )),
                ],
                if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _sectionLabel('Inactive Members (${inactive.length})'),
                  ...inactive.map((m) => _MemberCard(
                        member: m,
                        onEdit: () => _showForm(context, existing: m),
                        onToggleActive: () => _toggleActive(m),
                        onDelete: () => _confirmDelete(context, m),
                      )),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context),
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
      );

  void _toggleActive(TeamMember member) {
    setState(() {
      final idx = _members.indexWhere((m) => m.id == member.id);
      if (idx != -1) {
        _members[idx] = member.copyWith(isActive: !member.isActive);
      }
    });
  }

  void _showForm(BuildContext context, {TeamMember? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MemberForm(
        existing: existing,
        onSave: (member) {
          setState(() {
            if (existing != null) {
              final idx = _members.indexWhere((m) => m.id == existing.id);
              if (idx != -1) _members[idx] = member;
            } else {
              _members.add(member);
            }
          });
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, TeamMember member) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from the team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              setState(() => _members.removeWhere((m) => m.id == member.id));
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ── Member Card ──────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  Color get _roleColor => switch (member.role) {
        UserRole.admin => const Color(0xFF6A1B9A),
        UserRole.manager => AppTheme.primaryColor,
        UserRole.operator => AppTheme.secondaryColor,
        UserRole.viewer => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: _roleColor.withOpacity(0.15),
          child: Text(
            member.avatarInitials ?? '?',
            style: TextStyle(
              color: _roleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (!member.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Inactive',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.email,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _roleColor.withOpacity(0.3)),
              ),
              child: Text(
                member.role.label,
                style: TextStyle(
                  fontSize: 11,
                  color: _roleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(member.isActive ? 'Deactivate' : 'Activate'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (action) {
            if (action == 'edit') onEdit();
            if (action == 'toggle') onToggleActive();
            if (action == 'delete') onDelete();
          },
        ),
      ),
    );
  }
}

// ── Member Form ──────────────────────────────────────────────────────────────

class _MemberForm extends StatefulWidget {
  final TeamMember? existing;
  final ValueChanged<TeamMember> onSave;

  const _MemberForm({this.existing, required this.onSave});

  @override
  State<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends State<_MemberForm> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _notesCtrl;
  UserRole _role = UserRole.operator;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _emailCtrl = TextEditingController(text: m?.email ?? '');
    _phoneCtrl = TextEditingController(text: m?.phone ?? '');
    _notesCtrl = TextEditingController(text: m?.notes ?? '');
    _role = m?.role ?? UserRole.operator;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? 'Add Team Member' : 'Edit Member',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _field(_nameCtrl, 'Full Name *',
                  validator: (v) => v!.isEmpty ? 'Required' : null),
              _field(_emailCtrl, 'Email *',
                  keyboardType: TextInputType.emailAddress, validator: (v) {
                if (v!.isEmpty) return 'Required';
                if (!v.contains('@')) return 'Invalid email';
                return null;
              }),
              _field(_phoneCtrl, 'Phone', keyboardType: TextInputType.phone),
              // Role dropdown
              DropdownButtonFormField<UserRole>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role *'),
                items: UserRole.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(r.label),
                              Text(
                                r.description,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
              ),
              const SizedBox(height: 10),
              _field(_notesCtrl, 'Notes', maxLines: 2),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(
                      widget.existing == null ? 'Add Member' : 'Update Member'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
          {int maxLines = 1,
          String? Function(String?)? validator,
          TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
      );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final member = TeamMember(
      id: widget.existing?.id ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      role: _role,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      isActive: widget.existing?.isActive ?? true,
      createdAt: widget.existing?.createdAt,
    );
    widget.onSave(member);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.existing == null
            ? '${member.name} added to team!'
            : '${member.name} updated!'),
      ),
    );
  }
}
