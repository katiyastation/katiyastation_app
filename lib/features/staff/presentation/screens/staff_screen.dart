import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile == null) return;
    final data = await ref.read(supabaseProvider).from(SupabaseConstants.staffMembers)
        .select().eq('branch_id', profile.branchId ?? '').order('name');
    if (mounted) setState(() { _staff = List<Map<String, dynamic>>.from(data); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          TextButton.icon(icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Add Staff'), onPressed: () => _showAddDialog(context)),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Staff Members'), Tab(text: 'Salary')],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // Staff list
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _staff.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.badge_outlined, size: 64, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      Text('No staff members added', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: () => _showAddDialog(context), child: const Text('Add First Staff')),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _staff.length,
                      itemBuilder: (ctx, i) => _StaffCard(staff: _staff[i]).animate().fadeIn(delay: Duration(milliseconds: i * 30)),
                    ),
          // Salary tab
          _SalaryView(staff: _staff, ref: ref),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    String role = 'waiter';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Staff Member'),
      content: StatefulBuilder(builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
        const SizedBox(height: 12),
        TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: role,
          decoration: const InputDecoration(labelText: 'Role'),
          onChanged: (v) => set(() => role = v!),
          items: const [
            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
            DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
            DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Staff')),
            DropdownMenuItem(value: 'inventory', child: Text('Inventory Manager')),
            DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
          ],
        ),
        const SizedBox(height: 12),
        TextField(controller: salaryCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly Salary (NPR)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final profile = ref.read(authNotifierProvider).value;
          await ref.read(supabaseProvider).from(SupabaseConstants.staffMembers).insert({
            'id': const Uuid().v4(),
            'branch_id': profile?.branchId,
            'name': nameCtrl.text.trim(),
            'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
            'role': role,
            'monthly_salary': double.tryParse(salaryCtrl.text) ?? 0,
            'is_active': true,
            'created_at': DateTime.now().toIso8601String(),
          });
          if (context.mounted) { Navigator.pop(ctx); _load(); }
        }, child: const Text('Add')),
      ],
    ));
  }
}

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  const _StaffCard({required this.staff});

  Color _roleColor(String? role) {
    switch (role) {
      case 'cashier': return AppColors.roleCashier;
      case 'kitchen': return AppColors.roleKitchen;
      case 'inventory': return AppColors.roleInventory;
      case 'accountant': return AppColors.warning;
      default: return AppColors.roleWaiter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = staff['role'] as String? ?? 'waiter';
    final color = _roleColor(role);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text((staff['name'] as String).substring(0, 1).toUpperCase(),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(staff['name'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(staff['phone'] as String? ?? '—', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(role.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Text('NPR ${NumberFormat('#,##0').format((staff['monthly_salary'] as num?)?.toInt() ?? 0)}/mo',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class _SalaryView extends StatelessWidget {
  final List<Map<String, dynamic>> staff;
  final WidgetRef ref;
  const _SalaryView({required this.staff, required this.ref});

  @override
  Widget build(BuildContext context) {
    final total = staff.fold<double>(0, (s, m) => s + ((m['monthly_salary'] as num?)?.toDouble() ?? 0));
    return Column(
      children: [
        Container(
          color: AppColors.surface, padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.payments_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Monthly Salary Expense', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
              Text('NPR ${NumberFormat('#,##0.00').format(total)}',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: staff.isEmpty
          ? Center(child: Text('No staff added', style: GoogleFonts.outfit(color: AppColors.textSecondary)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: staff.length,
              itemBuilder: (ctx, i) {
                final m = staff[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Expanded(child: Text(m['name'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                    Text('NPR ${NumberFormat('#,##0').format((m['monthly_salary'] as num?)?.toInt() ?? 0)}',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ]),
                );
              },
            )),
      ],
    );
  }
}
