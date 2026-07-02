import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── Report data providers ───────────────────────────────────────────────────

final _reportBillsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.bills,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
});

final _reportExpensesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.expenses,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
});

// ────────────────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final fmt = NumberFormat('#,##0.00');
  String _timeframe = 'Today';

  DateTime get _startDate {
    final now = DateTime.now();
    if (_timeframe == 'Today') return DateTime(now.year, now.month, now.day);
    if (_timeframe == 'Weekly') return now.subtract(const Duration(days: 7));
    return DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(_reportBillsProvider);
    final expensesAsync = ref.watch(_reportExpensesProvider);

    final allBills = billsAsync.value ?? [];
    final allExpenses = expensesAsync.value ?? [];

    final start = _startDate;
    final filteredBills = allBills.where((b) {
      final dt = DateTime.tryParse(b['created_at'] as String? ?? '');
      return dt != null && dt.isAfter(start);
    }).toList();
    final filteredExpenses = allExpenses.where((e) {
      final dt = DateTime.tryParse(e['created_at'] as String? ?? '');
      return dt != null && dt.isAfter(start);
    }).toList();

    double sales = 0, credits = 0;
    for (final b in filteredBills) {
      final amt = (b['total_amount'] as num?)?.toDouble() ?? 0;
      if (b['payment_status'] == 'paid') sales += amt;
      if (b['payment_status'] == 'credit') credits += amt;
    }
    final expenses = filteredExpenses.fold<double>(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    final netProfit = sales - expenses;
    final profitColor = netProfit >= 0 ? AppColors.success : AppColors.error;
    final isLoading = billsAsync.isLoading || expensesAsync.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          DropdownButton<String>(
            value: _timeframe,
            dropdownColor: AppColors.surface,
            style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 13),
            underline: const SizedBox(),
            onChanged: (v) => setState(() => _timeframe = v!),
            items: const [
              DropdownMenuItem(value: 'Today', child: Text('Today')),
              DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Performance Summary ($_timeframe)', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _ReportSummaryCard('Gross Revenue', 'NPR ${fmt.format(sales)}', Icons.show_chart_rounded, AppColors.success),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Expenses', 'NPR ${fmt.format(expenses)}', Icons.payment_rounded, AppColors.error),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Net Profit', 'NPR ${fmt.format(netProfit)}', Icons.account_balance_wallet_rounded, profitColor),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _ReportSummaryCard('Udhaaro Outstanding', 'NPR ${fmt.format(credits)}', Icons.assignment_late_rounded, AppColors.warning),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Total Invoices', '${filteredBills.length} transactions', Icons.description_rounded, AppColors.info),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Financial Breakdown', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const SizedBox(height: 20),
                        _BreakdownRow('Sales Revenue', sales, AppColors.success),
                        const SizedBox(height: 12),
                        _BreakdownRow('Total Expenses', expenses, AppColors.error),
                        const SizedBox(height: 12),
                        _BreakdownRow('Outstanding Credits', credits, AppColors.warning),
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Estimated Net Profit', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                            Text('NPR ${fmt.format(netProfit)}', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16, color: profitColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _ReportSummaryCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 14),
            Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(label, style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label; final double val; final Color color;
  const _BreakdownRow(this.label, this.val, this.color);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
        ]),
        Text('NPR ${fmt.format(val)}', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
