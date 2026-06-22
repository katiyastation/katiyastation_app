import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Real-time purchases stream
final purchasesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();
  return supabase
      .from(SupabaseConstants.purchases)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('created_at', ascending: false)
      .map((rows) => List<Map<String, dynamic>>.from(rows));
});

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});
  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final fmt = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesProvider);
    final purchases = purchasesAsync.value ?? [];
    final totalSpend = purchases.fold<double>(0, (s, p) => s + ((p['total_amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Purchase Management'),
        actions: [
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Purchase'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface, padding: const EdgeInsets.all(16),
            child: Row(children: [
              _SC('Total Purchases', '${purchases.length}', AppColors.info),
              const SizedBox(width: 12),
              _SC('Total Spent', 'NPR ${fmt.format(totalSpend)}', AppColors.error),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: purchasesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
            data: (_) => purchases.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No purchases recorded', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => _showAddDialog(context), child: const Text('Record Purchase')),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: purchases.length,
                  itemBuilder: (ctx, i) {
                    final p = purchases[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.receipt_long_rounded, color: AppColors.info, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['supplier_name'] ?? 'Unknown Supplier', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(p['notes'] ?? 'Purchase order', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('NPR ${fmt.format((p['total_amount'] as num?)?.toDouble() ?? 0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text(DateFormat('dd MMM yyyy').format(DateTime.parse(p['created_at'] as String)),
                              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
                        ]),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                  },
                ),
          )),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final supplierCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Record Purchase'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: supplierCtrl, decoration: const InputDecoration(labelText: 'Supplier Name *')),
        const SizedBox(height: 12),
        TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total Amount (NPR) *')),
        const SizedBox(height: 12),
        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final profile = ref.read(authNotifierProvider).value;
          await ref.read(supabaseProvider).from(SupabaseConstants.purchases).insert({
            'id': const Uuid().v4(),
            'branch_id': profile?.branchId,
            'supplier_name': supplierCtrl.text.trim(),
            'total_amount': double.tryParse(amountCtrl.text) ?? 0,
            'notes': notesCtrl.text.trim(),
            'status': 'received',
            'created_at': DateTime.now().toIso8601String(),
          });
          ref.invalidate(purchasesProvider);
          if (context.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }
}

class _SC extends StatelessWidget {
  final String l, v; final Color c;
  const _SC(this.l, this.v, this.c);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: GoogleFonts.outfit(fontSize: 11, color: c)),
      Text(v, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]),
  ));
}
