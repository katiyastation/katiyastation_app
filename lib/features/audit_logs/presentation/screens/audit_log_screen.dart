import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final auditLogsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();
  return supabase
      .from(SupabaseConstants.auditLogs)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('created_at')
      .map((rows) {
        final list = List<Map<String, dynamic>>.from(rows);
        // Sort descending by created_at since .stream() doesn't support descending order
        list.sort((a, b) =>
            (b['created_at'] as String).compareTo(a['created_at'] as String));
        return list.take(100).toList();
      });
});

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});
  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _selectedAction = 'All';
  String _search = '';

  final List<String> _actionFilters = [
    'All',
    'create',
    'update',
    'delete',
    'login',
    'logout',
    'refund',
    'cancel',
    'credit',
  ];

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Audit Logs'),
        actions: [
          // Refresh button kept as a visual cue; stream auto-updates
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(auditLogsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by user, action, or description...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          // Action filter chips
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _actionFilters.length,
              itemBuilder: (_, i) {
                final f = _actionFilters[i];
                final isSelected = f == _selectedAction;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAction = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(f == 'All' ? 'All' : f.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: logsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (logs) {
                var filtered = logs.where((log) {
                  final action = (log['action'] as String? ?? '').toLowerCase();
                  final user = (log['user_name'] as String? ?? '').toLowerCase();
                  final desc = (log['description'] as String? ?? '').toLowerCase();

                  if (_selectedAction != 'All' &&
                      !action.contains(_selectedAction.toLowerCase())) {
                    return false;
                  }

                  if (_search.isNotEmpty &&
                      !action.contains(_search) &&
                      !user.contains(_search) &&
                      !desc.contains(_search)) {
                    return false;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('No audit logs found',
                            style:
                                GoogleFonts.outfit(color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) =>
                      _AuditLogEntry(log: filtered[i])
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: i * 15)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogEntry extends StatelessWidget {
  final Map<String, dynamic> log;
  const _AuditLogEntry({required this.log});

  Color _actionColor(String action) {
    switch (action.toLowerCase()) {
      case 'create': return AppColors.success;
      case 'delete': return AppColors.error;
      case 'update': return AppColors.info;
      case 'refund': return AppColors.warning;
      case 'cancel': return AppColors.error;
      case 'login': return AppColors.primary;
      case 'logout': return AppColors.textSecondary;
      case 'credit': return AppColors.warning;
      default: return AppColors.textSecondary;
    }
  }

  IconData _actionIcon(String action) {
    switch (action.toLowerCase()) {
      case 'create': return Icons.add_circle_rounded;
      case 'delete': return Icons.delete_rounded;
      case 'update': return Icons.edit_rounded;
      case 'refund': return Icons.undo_rounded;
      case 'cancel': return Icons.cancel_rounded;
      case 'login': return Icons.login_rounded;
      case 'logout': return Icons.logout_rounded;
      case 'credit': return Icons.account_balance_wallet_rounded;
      default: return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = (log['action'] as String? ?? 'action');
    final color = _actionColor(action);
    final icon = _actionIcon(action);
    final userName = log['user_name'] as String? ?? 'System';
    final userRole = log['user_role'] as String? ?? '';
    final description = log['description'] as String? ?? '';
    final module = log['module'] as String? ?? '';
    final createdAt = log['created_at'] != null
        ? DateFormat('dd MMM yyyy, HH:mm:ss')
            .format(DateTime.parse(log['created_at'] as String).toLocal())
        : '—';
    final device = log['device'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(action.toUpperCase(),
                          style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 0.5)),
                    ),
                    if (module.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(module,
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                    const Spacer(),
                    Text(createdAt,
                        style: GoogleFonts.outfit(
                            fontSize: 10, color: AppColors.textHint)),
                  ],
                ),
                const SizedBox(height: 4),
                if (description.isNotEmpty)
                  Text(description,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded,
                        size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text('$userName${userRole.isNotEmpty ? ' ($userRole)' : ''}',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textSecondary)),
                    if (device != null) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.devices_rounded,
                          size: 12, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(device,
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: AppColors.textHint)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
