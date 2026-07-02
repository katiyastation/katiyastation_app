// ============================================================
// KATIYA STATION RMS — BRANCH USERS (Manager)
// Lets a branch manager reset the login password for any user
// account in their own branch. Branch scoping is enforced
// server-side too (resolveBranchScope), this screen never lets
// a manager pick another branch.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/reset_password_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final branchUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.users,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final list = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  list.sort((a, b) => (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? ''));
  return list;
});

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _search = '';

  static const _roleColors = {
    'branch_manager': Color(0xFF42A5F5),
    'cashier': Color(0xFF66BB6A),
    'waiter': Color(0xFFFF7043),
    'kitchen': Color(0xFFFFCA28),
    'inventory': Color(0xFF26C6DA),
    'accountant': Color(0xFFEC407A),
  };

  static const _roleLabels = {
    'branch_manager': 'Branch Manager',
    'cashier': 'Cashier',
    'waiter': 'Waiter',
    'kitchen': 'Kitchen',
    'inventory': 'Inventory',
    'accountant': 'Accountant',
  };

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(branchUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Branch Users')),
      body: Column(
        children: [
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
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (users) {
                final filtered = _search.isEmpty
                    ? users
                    : users.where((u) {
                        final name = (u['full_name'] as String? ?? '').toLowerCase();
                        final email = (u['email'] as String? ?? '').toLowerCase();
                        final role = (u['role'] as String? ?? '').toLowerCase();
                        return name.contains(_search) || email.contains(_search) || role.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text('No users found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final user = filtered[i];
                    final name = user['full_name'] as String? ?? '—';
                    final email = user['email'] as String? ?? '—';
                    final role = user['role'] as String? ?? '—';
                    final isActive = user['is_active'] as bool? ?? true;
                    final roleColor = _roleColors[role] ?? AppColors.textSecondary;
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: roleColor.withValues(alpha: 0.15),
                          child: Text(initial,
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: roleColor)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(
                                  child: Text(name,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                ),
                                if (!isActive) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.block_rounded, size: 12, color: AppColors.error),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(email, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(_roleLabels[role] ?? role,
                              style: GoogleFonts.outfit(fontSize: 10, color: roleColor, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.lock_reset_rounded, size: 20, color: AppColors.primary),
                          tooltip: 'Reset Password',
                          onPressed: () => showResetPasswordDialog(context, userId: user['id'] as String, userName: name),
                        ),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
