import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(authNotifierProvider);
    final supabase = ref.watch(supabaseProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox();
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                backgroundColor: AppColors.surface,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good ${_greeting()}, ${profile.fullName.split(' ').first}!',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
                    onPressed: () => context.go('/notifications'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manager dashboard
                      if (profile.isBranchManager) ...[
                        const _SectionHeader('Today\'s Overview'),
                        const SizedBox(height: 16),
                        _ManagerStatsGrid(supabase: supabase),
                        const SizedBox(height: 24),
                        const _SectionHeader('Quick Actions'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ]
                      // Cashier dashboard
                      else if (profile.isCashier) ...[
                        const _SectionHeader('Cashier Station'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ]
                      // Waiter dashboard
                      else if (profile.isWaiter) ...[
                        const _SectionHeader('My Tables'),
                        const SizedBox(height: 16),
                        _WaiterQuickNav(),
                      ]
                      // Kitchen dashboard
                      else if (profile.isKitchen) ...[
                        const _SectionHeader('Kitchen Orders'),
                        const SizedBox(height: 16),
                        _KitchenQuickNav(),
                      ]
                      else ...[
                        const _SectionHeader('Welcome'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
}

class _ManagerStatsGrid extends ConsumerWidget {
  final SupabaseClient supabase;
  const _ManagerStatsGrid({required this.supabase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FutureBuilder(
      future: Future.wait([
        supabase.from(SupabaseConstants.bills)
            .select('total_amount, payment_status')
            .gte('created_at', '${today}T00:00:00')
            .lte('created_at', '${today}T23:59:59'),
        supabase.from(SupabaseConstants.expenses)
            .select('amount')
            .gte('created_at', '${today}T00:00:00'),
        supabase.from(SupabaseConstants.kots)
            .select('id')
            .eq('status', 'pending'),
        supabase.from(SupabaseConstants.creditRecords)
            .select('credit_amount, paid_amount')
            .neq('status', 'paid'),
      ]),
      builder: (context, snapshot) {
        double todaySales = 0;
        double expenses = 0;
        int pendingKots = 0;
        double creditOutstanding = 0;

        if (snapshot.hasData) {
          final bills = snapshot.data![0] as List;
          final expenseList = snapshot.data![1] as List;
          final kots = snapshot.data![2] as List;
          final credits = snapshot.data![3] as List;

          todaySales = bills
              .where((b) => b['payment_status'] == 'paid')
              .fold(0.0, (s, b) => s + ((b['total_amount'] as num?)?.toDouble() ?? 0));
          expenses = expenseList.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
          pendingKots = kots.length;
          creditOutstanding = credits.fold(0.0, (s, c) =>
              s + (((c['credit_amount'] as num?)?.toDouble() ?? 0) - ((c['paid_amount'] as num?)?.toDouble() ?? 0)));
        }

        final fmt = NumberFormat('#,##0.00');
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _StatCard('Today\'s Sales', 'NPR ${fmt.format(todaySales)}', Icons.trending_up_rounded, AppColors.success),
            _StatCard('Today\'s Expenses', 'NPR ${fmt.format(expenses)}', Icons.money_off_rounded, AppColors.error),
            _StatCard('Pending KOTs', pendingKots.toString(), Icons.receipt_outlined, AppColors.warning),
            _StatCard('Credit Outstanding', 'NPR ${fmt.format(creditOutstanding)}', Icons.account_balance_wallet_rounded, AppColors.info),
          ].animate(interval: 80.ms).fadeIn().slideY(begin: 0.2),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(label,
                  style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final String role;
  const _QuickActionsGrid({required this.role});

  @override
  Widget build(BuildContext context) {
    final actions = _getActions(role, context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _ActionCard(
        icon: actions[i]['icon'] as IconData,
        label: actions[i]['label'] as String,
        color: actions[i]['color'] as Color,
        onTap: actions[i]['onTap'] as VoidCallback,
      ),
    );
  }

  List<Map<String, dynamic>> _getActions(String role, BuildContext context) {
    switch (role) {
      case AppConstants.roleBranchManager:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.receipt_long_rounded, 'label': 'Payments', 'color': AppColors.info, 'onTap': () => context.go('/payment-history')},
          {'icon': Icons.restaurant_menu_rounded, 'label': 'Menu', 'color': AppColors.primary, 'onTap': () => context.go('/menu')},
          {'icon': Icons.inventory_2_rounded, 'label': 'Inventory', 'color': AppColors.roleInventory, 'onTap': () => context.go('/inventory')},
          {'icon': Icons.bar_chart_rounded, 'label': 'Reports', 'color': AppColors.warning, 'onTap': () => context.go('/reports')},
          {'icon': Icons.people_rounded, 'label': 'Staff', 'color': AppColors.roleKitchen, 'onTap': () => context.go('/staff')},
          {'icon': Icons.account_balance_wallet_rounded, 'label': 'Credit', 'color': AppColors.error, 'onTap': () => context.go('/credit')},
          {'icon': Icons.event_seat_rounded, 'label': 'Reservations', 'color': AppColors.roleCashier, 'onTap': () => context.go('/reservations')},
        ];
      case AppConstants.roleCashier:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.point_of_sale_rounded, 'label': 'Cashier', 'color': AppColors.primary, 'onTap': () => context.go('/cashier')},
          {'icon': Icons.receipt_long_rounded, 'label': 'Payments', 'color': AppColors.info, 'onTap': () => context.go('/payment-history')},
          {'icon': Icons.event_seat_rounded, 'label': 'Reservations', 'color': AppColors.roleCashier, 'onTap': () => context.go('/reservations')},
          {'icon': Icons.people_rounded, 'label': 'Customers', 'color': AppColors.roleManager, 'onTap': () => context.go('/customers')},
          {'icon': Icons.account_balance_wallet_rounded, 'label': 'Credit', 'color': AppColors.error, 'onTap': () => context.go('/credit')},
        ];
      default:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.kitchen_rounded, 'label': 'Kitchen', 'color': AppColors.roleKitchen, 'onTap': () => context.go('/kitchen')},
        ];
    }
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _WaiterQuickNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.table_restaurant_rounded),
          label: const Text('View Tables & Take Orders'),
          onPressed: () => context.go('/tables'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.fingerprint_rounded),
          label: const Text('Mark Attendance'),
          onPressed: () => context.go('/attendance'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
      ],
    );
  }
}

class _KitchenQuickNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.kitchen_rounded),
      label: const Text('Open Kitchen Display'),
      onPressed: () => context.go('/kitchen'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }
}
