import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── Providers ──────────────────────────────────────────────────
final allUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final List<dynamic> data = await supabase.rpc('get_all_users');
  final list = List<Map<String, dynamic>>.from(data);
  list.sort((a, b) {
    final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
    final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
    return bTime.compareTo(aTime);
  });
  return list;
});

final allBranchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final data = await supabase.from(SupabaseConstants.branches).select('id, name').order('name');
  return List<Map<String, dynamic>>.from(data);
});

// ── Super Admin Portal ─────────────────────────────────────────
class SuperAdminPortal extends ConsumerStatefulWidget {
  const SuperAdminPortal({super.key});
  @override
  ConsumerState<SuperAdminPortal> createState() => _SuperAdminPortalState();
}

class _SuperAdminPortalState extends ConsumerState<SuperAdminPortal>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Super Admin Portal',
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text('Katiya Station — Developer Console',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ]),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'User Accounts'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Access Logs'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Create User'),
            onPressed: () => _showCreateUserDialog(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Tab 1: Users List ────────────────────────────────
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by name, email or role...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (users) {
                  final filtered = _search.isEmpty
                      ? users
                      : users.where((u) {
                          final name = (u['full_name'] as String? ?? '').toLowerCase();
                          final email = (u['email'] as String? ?? '').toLowerCase();
                          final role = (u['role'] as String? ?? '').toLowerCase();
                          return name.contains(_search) ||
                              email.contains(_search) ||
                              role.contains(_search);
                        }).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _UserCard(
                      user: filtered[i],
                      onBlock: () => _toggleBlock(filtered[i]),
                      onEdit: () => _showEditUserDialog(context, filtered[i]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
                  );
                },
              ),
            ),
          ]),

          // ── Tab 2: Access Logs ───────────────────────────────
          const _AccessLogsTab(),
        ],
      ),
    );
  }

  Future<void> _toggleBlock(Map<String, dynamic> user) async {
    final isActive = user['is_active'] as bool? ?? true;
    final name = user['full_name'] as String? ?? 'this user';
    final action = isActive ? 'Block' : 'Unblock';

    // Capture messenger before async gap
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Account'),
        content: Text(
            '${isActive ? 'This will prevent' : 'This will restore'} $name\'s ability to log in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? AppColors.error : AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(supabaseProvider).rpc('admin_set_user_active', params: {
        'p_target_user_id': user['id'],
        'p_is_active': !isActive,
      });
      ref.invalidate(allUsersProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('$name has been ${isActive ? 'blocked' : 'unblocked'}.'),
        backgroundColor: isActive ? AppColors.error : AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  void _showCreateUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'cashier';
    String? selectedBranchId;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final branchesAsync = ref.watch(allBranchesProvider);
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.person_add_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Create User Account',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email Address *', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                      labelText: 'Role *', prefixIcon: Icon(Icons.badge_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                    DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                    DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Staff')),
                    DropdownMenuItem(value: 'inventory', child: Text('Inventory Manager')),
                    DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
                  ],
                  onChanged: (v) => setS(() => selectedRole = v ?? 'cashier'),
                ),
                const SizedBox(height: 12),
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (branches) => DropdownButtonFormField<String>(
                    initialValue: selectedBranchId,
                    decoration: const InputDecoration(
                        labelText: 'Assign Branch', prefixIcon: Icon(Icons.store_outlined)),
                    hint: const Text('Select branch'),
                    items: branches.map((b) => DropdownMenuItem<String>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String),
                        )).toList(),
                    onChanged: (v) => setS(() => selectedBranchId = v),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Create Account'),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    emailCtrl.text.trim().isEmpty ||
                    passCtrl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Fill all fields. Password min 6 chars.')));
                  return;
                }
                Navigator.pop(ctx);
                await _createUser(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  password: passCtrl.text,
                  role: selectedRole,
                  branchId: selectedBranchId,
                );
              },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final adminClient = ref.read(supabaseProvider);
      
      // Call secure SQL RPC to provision the user in auth.users and user_profiles
      await adminClient.rpc('admin_create_auth_user', params: {
        'p_email': email,
        'p_password': password,
        'p_full_name': name,
        'p_role': role,
        'p_branch_id': branchId,
        'p_invited_by': adminClient.auth.currentUser!.id,
      });

      ref.invalidate(allUsersProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('✓ Account created for $name ($email)'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['full_name'] as String? ?? '');
    String selectedRole = user['role'] as String? ?? 'cashier';
    String? selectedBranchId = user['branch_id'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final branchesAsync = ref.watch(allBranchesProvider);
        return AlertDialog(
          title: Text('Edit — ${user['full_name']}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                  DropdownMenuItem(value: 'kitchen', child: Text('Kitchen')),
                  DropdownMenuItem(value: 'inventory', child: Text('Inventory')),
                  DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
                ],
                onChanged: (v) => setS(() => selectedRole = v ?? selectedRole),
              ),
              const SizedBox(height: 12),
              branchesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox(),
                data: (branches) => DropdownButtonFormField<String>(
                  initialValue: selectedBranchId,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  hint: const Text('Select branch'),
                  items: branches.map((b) => DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String),
                      )).toList(),
                  onChanged: (v) => setS(() => selectedBranchId = v),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  await ref.read(supabaseProvider).rpc('admin_update_user', params: {
                    'p_target_user_id': user['id'],
                    'p_role': selectedRole,
                    'p_branch_id': selectedBranchId,
                    'p_full_name': nameCtrl.text.trim(),
                  });
                  ref.invalidate(allUsersProvider);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('User updated successfully'),
                      backgroundColor: AppColors.success));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('Error: $e'), backgroundColor: AppColors.error));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      }),
    );
  }
}

// ── User Card ──────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onBlock;
  final VoidCallback onEdit;

  const _UserCard({required this.user, required this.onBlock, required this.onEdit});

  static const _roleColors = {
    'super_admin': Color(0xFFE040FB),
    'branch_manager': Color(0xFF42A5F5),
    'cashier': Color(0xFF66BB6A),
    'waiter': Color(0xFFFF7043),
    'kitchen': Color(0xFFFFCA28),
    'inventory': Color(0xFF26C6DA),
    'accountant': Color(0xFFEC407A),
  };

  static const _roleLabels = {
    'super_admin': 'Super Admin',
    'branch_manager': 'Branch Manager',
    'cashier': 'Cashier',
    'waiter': 'Waiter',
    'kitchen': 'Kitchen',
    'inventory': 'Inventory',
    'accountant': 'Accountant',
  };

  @override
  Widget build(BuildContext context) {
    final isActive = user['is_active'] as bool? ?? true;
    final name = user['full_name'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final role = user['role'] as String? ?? '—';
    final branch = user['branch_name'] as String? ?? 'No branch';
    final roleColor = _roleColors[role] ?? AppColors.textSecondary;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.border
              : AppColors.error.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(initial,
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.w700, color: roleColor)),
          ),
          if (!isActive)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 2)),
              ),
            ),
        ]),
        title: Row(children: [
          Expanded(
            child: Text(name,
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.textPrimary : AppColors.textHint,
                    decoration: isActive ? null : TextDecoration.lineThrough)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _roleLabels[role] ?? role,
              style: GoogleFonts.outfit(
                  fontSize: 10, color: roleColor, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 2),
          Text(email,
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          Row(children: [
            const Icon(Icons.store_outlined, size: 12, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text(branch,
                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint)),
            if (!isActive) ...[
              const SizedBox(width: 8),
              const Icon(Icons.block_rounded, size: 12, color: AppColors.error),
              const SizedBox(width: 2),
              Text('BLOCKED',
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700)),
            ],
          ]),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
          onSelected: (s) {
            if (s == 'edit') onEdit();
            if (s == 'block') onBlock();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Edit User'),
                ])),
            PopupMenuItem(
              value: 'block',
              child: Row(children: [
                Icon(
                    isActive ? Icons.block_rounded : Icons.check_circle_outline,
                    size: 16,
                    color: isActive ? AppColors.error : AppColors.success),
                const SizedBox(width: 8),
                Text(isActive ? 'Block Login' : 'Restore Access',
                    style: TextStyle(
                        color: isActive ? AppColors.error : AppColors.success)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Access Logs Tab ────────────────────────────────────────────
class _AccessLogsTab extends ConsumerWidget {
  const _AccessLogsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase
          .from('user_access_logs')
          .select('*, performed:user_profiles!performed_by(full_name), target:user_profiles!target_user(full_name)')
          .order('created_at', ascending: false)
          .limit(100),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        final logs = snap.data ?? [];
        if (logs.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.history_rounded, size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('No access logs yet',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (_, i) {
            final log = logs[i];
            final action = log['action'] as String? ?? '—';
            final performer = (log['performed'] as Map?)?['full_name'] as String? ?? 'System';
            final target = (log['target'] as Map?)?['full_name'] as String? ?? '—';
            final at = log['created_at'] != null
                ? DateTime.parse(log['created_at'] as String).toLocal()
                : null;

            final (color, icon) = switch (action) {
              'created'      => (AppColors.success, Icons.person_add_rounded),
              'blocked'      => (AppColors.error, Icons.block_rounded),
              'unblocked'    => (AppColors.success, Icons.check_circle_rounded),
              'role_changed' => (AppColors.info, Icons.badge_rounded),
              'deleted'      => (AppColors.error, Icons.delete_rounded),
              _              => (AppColors.textSecondary, Icons.info_rounded),
            };

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(action.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.outfit(
                            fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                    Text('By: $performer | Target: $target',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ),
                if (at != null)
                  Text(
                    '${at.day}/${at.month} ${at.hour}:${at.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textHint),
                  ),
              ]),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 20));
          },
        );
      },
    );
  }
}
