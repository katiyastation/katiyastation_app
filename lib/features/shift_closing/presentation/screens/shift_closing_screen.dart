import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ShiftClosingScreen extends ConsumerStatefulWidget {
  const ShiftClosingScreen({super.key});
  @override
  ConsumerState<ShiftClosingScreen> createState() => _ShiftClosingScreenState();
}

class _ShiftClosingScreenState extends ConsumerState<ShiftClosingScreen> {
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _summary;

  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _loadTodaySummary();
  }

  Future<void> _loadTodaySummary() async {
    setState(() => _loading = true);
    final supabase = ref.read(supabaseProvider);
    final profile = ref.read(authNotifierProvider).value;
    if (profile == null) {
      setState(() => _loading = false);
      return;
    }

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final bills = await supabase
        .from(SupabaseConstants.bills)
        .select()
        .eq('branch_id', profile.branchId ?? '')
        .gte('created_at', startOfDay.toIso8601String())
        .lt('created_at', endOfDay.toIso8601String());

    final List<Map<String, dynamic>> billList = List<Map<String, dynamic>>.from(bills);

    double cashTotal = 0;
    double cardTotal = 0;
    double esewaTotal = 0;
    double khaltiTotal = 0;
    double fonepayTotal = 0;
    double creditTotal = 0;
    double refundTotal = 0;
    double totalRevenue = 0;
    double totalVat = 0;
    double totalDiscount = 0;
    double totalServiceCharge = 0;
    int billCount = 0;

    for (final b in billList) {
      final method = b['payment_method'] as String? ?? 'cash';
      final amount = (b['total_amount'] as num?)?.toDouble() ?? 0;
      final status = b['payment_status'] as String? ?? 'paid';

      if (status == 'refunded') {
        refundTotal += amount;
        continue;
      }

      totalRevenue += amount;
      totalVat += (b['vat_amount'] as num?)?.toDouble() ?? 0;
      totalDiscount += (b['discount'] as num?)?.toDouble() ?? 0;
      totalServiceCharge += (b['service_charge'] as num?)?.toDouble() ?? 0;
      billCount++;

      switch (method) {
        case 'cash': cashTotal += amount; break;
        case 'card': cardTotal += amount; break;
        case 'esewa': esewaTotal += amount; break;
        case 'khalti': khaltiTotal += amount; break;
        case 'fonepay': fonepayTotal += amount; break;
        case 'credit': creditTotal += amount; break;
      }
    }

    setState(() {
      _summary = {
        'cash': cashTotal,
        'card': cardTotal,
        'esewa': esewaTotal,
        'khalti': khaltiTotal,
        'fonepay': fonepayTotal,
        'credit': creditTotal,
        'refund': refundTotal,
        'total_revenue': totalRevenue,
        'total_vat': totalVat,
        'total_discount': totalDiscount,
        'total_service_charge': totalServiceCharge,
        'bill_count': billCount,
        'net_revenue': totalRevenue - refundTotal,
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shift Closing'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            onPressed: _loadTodaySummary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _summary == null
              ? const Center(child: Text('Unable to load summary'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Banner
                      _DateBanner(),
                      const SizedBox(height: 20),

                      // Revenue Overview
                      const _SectionHeader('Revenue Overview'),
                      const SizedBox(height: 12),
                      _OverviewCards(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 20),

                      // Payment Method Breakdown
                      const _SectionHeader('Payment Breakdown'),
                      const SizedBox(height: 12),
                      _PaymentBreakdown(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 20),

                      // Deductions
                      const _SectionHeader('Adjustments'),
                      const SizedBox(height: 12),
                      _AdjustmentSection(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 32),

                      // Submit Button
                      if (profile?.isBranchManager == true ||
                          profile?.isCashier == true)
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.onPrimary))
                                : const Icon(Icons.lock_clock_rounded),
                            label: const Text('Close Shift & Generate Report'),
                            onPressed: _submitting
                                ? null
                                : () => _closeShift(context, profile),
                          ),
                        ).animate().fadeIn(),
                    ],
                  ),
                ),
    );
  }

  Future<void> _closeShift(BuildContext context, dynamic profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Shift'),
        content: const Text(
            'This will record the shift closing for today. The cashier summary will be saved. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close Shift')),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _submitting = true);

    try {
      final supabase = ref.read(supabaseProvider);
      await supabase.from(SupabaseConstants.shiftClosings).insert({
        'id': const Uuid().v4(),
        'branch_id': profile?.branchId,
        'cashier_id': profile?.id,
        'cashier_name': profile?.fullName,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'cash_total': _summary!['cash'],
        'card_total': _summary!['card'],
        'esewa_total': _summary!['esewa'],
        'khalti_total': _summary!['khalti'],
        'fonepay_total': _summary!['fonepay'],
        'credit_total': _summary!['credit'],
        'refund_total': _summary!['refund'],
        'total_revenue': _summary!['total_revenue'],
        'net_revenue': _summary!['net_revenue'],
        'total_vat': _summary!['total_vat'],
        'total_discount': _summary!['total_discount'],
        'total_service_charge': _summary!['total_service_charge'],
        'bill_count': _summary!['bill_count'],
        'status': 'pending_approval',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift closed successfully! Awaiting manager approval.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }

    setState(() => _submitting = false);
  }
}

class _DateBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A00), Color(0xFF2D1500)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today\'s Shift',
                  style: GoogleFonts.outfit(
                      fontSize: 14, color: AppColors.textSecondary)),
              Text(DateFormat('EEEE, dd MMMM yyyy').format(now),
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _OverviewCards({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2,
      children: [
        _StatCard('Total Bills', '${summary['bill_count']}', Icons.receipt_long_rounded, AppColors.info),
        _StatCard('Gross Revenue', 'NPR ${fmt.format(summary['total_revenue'])}',
            Icons.trending_up_rounded, AppColors.success),
        _StatCard('Total Refunds', 'NPR ${fmt.format(summary['refund'])}',
            Icons.undo_rounded, AppColors.error),
        _StatCard('Net Revenue', 'NPR ${fmt.format(summary['net_revenue'])}',
            Icons.account_balance_rounded, AppColors.primary),
      ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(value,
                    style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _PaymentBreakdown({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final methods = [
      ('Cash', 'cash', Icons.money_rounded, AppColors.success),
      ('Card', 'card', Icons.credit_card_rounded, AppColors.info),
      ('eSewa', 'esewa', Icons.phone_android_rounded, AppColors.primary),
      ('Khalti', 'khalti', Icons.account_balance_wallet_rounded, const Color(0xFF5C2D91)),
      ('FonePay', 'fonepay', Icons.qr_code_scanner_rounded, AppColors.warning),
      ('Credit', 'credit', Icons.receipt_long_rounded, AppColors.error),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: methods.asMap().entries.map((entry) {
          final i = entry.key;
          final (label, key, icon, color) = entry.value;
          final amount = (summary[key] as num?)?.toDouble() ?? 0;
          return Column(
            children: [
              if (i > 0) const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(icon, color: color, size: 20),
                title: Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: AppColors.textPrimary)),
                trailing: Text(
                  'NPR ${fmt.format(amount)}',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amount > 0 ? color : AppColors.textHint,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _AdjustmentSection extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _AdjustmentSection({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _AdjRow('Total VAT Collected', summary['total_vat'] as double, AppColors.info, fmt),
          const Divider(height: 1),
          _AdjRow('Total Discounts', summary['total_discount'] as double, AppColors.warning, fmt),
          const Divider(height: 1),
          _AdjRow('Service Charges', summary['total_service_charge'] as double, AppColors.success, fmt),
        ],
      ),
    );
  }
}

class _AdjRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final NumberFormat fmt;
  const _AdjRow(this.label, this.amount, this.color, this.fmt);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label,
          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
      trailing: Text('NPR ${fmt.format(amount)}',
          style: GoogleFonts.outfit(
              fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5));
  }
}
