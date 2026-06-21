import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final fmt = NumberFormat('#,##0.00');
  String _timeframe = 'Today';
  double _sales = 0;
  double _expenses = 0;
  double _credits = 0;
  int _ordersCount = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadReport(); }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final profile = ref.read(authNotifierProvider).value;
    if (profile == null) return;
    final supabase = ref.read(supabaseProvider);

    DateTime start = DateTime.now();
    final now = DateTime.now();
    if (_timeframe == 'Today') {
      start = DateTime(now.year, now.month, datePart(now.day));
    } else if (_timeframe == 'Weekly') {
      start = now.subtract(const Duration(days: 7));
    } else {
      start = DateTime(now.year, now.month, 1);
    }

    try {
      final bills = await supabase.from(SupabaseConstants.bills)
          .select('total_amount, payment_status')
          .eq('branch_id', profile.branchId ?? '')
          .gte('created_at', start.toIso8601String());

      final expenseData = await supabase.from(SupabaseConstants.expenses)
          .select('amount')
          .eq('branch_id', profile.branchId ?? '')
          .gte('created_at', start.toIso8601String());

      double totalSales = 0;
      double totalCredits = 0;
      for (final b in bills) {
        final amt = (b['total_amount'] as num?)?.toDouble() ?? 0;
        if (b['payment_status'] == 'paid') {
          totalSales += amt;
        } else if (b['payment_status'] == 'credit') {
          totalCredits += amt;
        }
      }

      double totalExpenses = expenseData.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));

      if (mounted) {
        setState(() {
          _sales = totalSales;
          _credits = totalCredits;
          _expenses = totalExpenses;
          _ordersCount = bills.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int datePart(int val) => val;

  @override
  Widget build(BuildContext context) {
    final netProfit = _sales - _expenses;
    final profitColor = netProfit >= 0 ? AppColors.success : AppColors.error;

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
            onChanged: (v) {
              setState(() => _timeframe = v!);
              _loadReport();
            },
            items: const [
              DropdownMenuItem(value: 'Today', child: Text('Today')),
              DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
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
                      _ReportSummaryCard('Gross Revenue', 'NPR ${fmt.format(_sales)}', Icons.show_chart_rounded, AppColors.success),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Expenses', 'NPR ${fmt.format(_expenses)}', Icons.payment_rounded, AppColors.error),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Net Profit', 'NPR ${fmt.format(netProfit)}', Icons.account_balance_wallet_rounded, profitColor),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _ReportSummaryCard('Udhaaro Outstanding', 'NPR ${fmt.format(_credits)}', Icons.assignment_late_rounded, AppColors.warning),
                      const SizedBox(width: 12),
                      _ReportSummaryCard('Total Invoices', '$_ordersCount transactions', Icons.description_rounded, AppColors.info),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Financial Breakdown
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
                        _BreakdownRow('Sales Revenue', _sales, AppColors.success),
                        const SizedBox(height: 12),
                        _BreakdownRow('Total Expenses', _expenses, AppColors.error),
                        const SizedBox(height: 12),
                        _BreakdownRow('Outstanding Credits', _credits, AppColors.warning),
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
