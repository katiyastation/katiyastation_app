import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/inventory_entities.dart';

final inventoryProvider = StreamProvider<List<InventoryItem>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();
  return supabase.from(SupabaseConstants.inventoryItems).stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '').order('name')
      .map((rows) => rows.map((r) => InventoryItem.fromJson(r)).toList());
});

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _filter = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Item'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface, padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(
                decoration: const InputDecoration(hintText: 'Search items...', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              )),
              const SizedBox(width: 12),
              ...['all', 'low', 'out'].map((f) => GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _filter == f ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _filter == f ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(f.toUpperCase(), style: GoogleFonts.outfit(fontSize: 11, color: _filter == f ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ),
              )).toList(),
            ]),
          ),
          const Divider(height: 1),
          itemsAsync.when(
            loading: () => const SizedBox(height: 60, child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (items) {
              final low = items.where((i) => i.isLow).length;
              final out = items.where((i) => i.isOut).length;
              return Container(
                color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  _SChip('Total', '${items.length}', AppColors.info),
                  const SizedBox(width: 8),
                  _SChip('Low Stock', '$low', AppColors.warning),
                  const SizedBox(width: 8),
                  _SChip('Out of Stock', '$out', AppColors.error),
                ]),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                var filtered = items.where((i) {
                  if (_search.isNotEmpty && !i.name.toLowerCase().contains(_search)) return false;
                  if (_filter == 'low') return i.isLow;
                  if (_filter == 'out') return i.isOut;
                  return true;
                }).toList();

                if (filtered.isEmpty) return Center(child: Text('No items found', style: GoogleFonts.outfit(color: AppColors.textSecondary)));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _InventoryTile(item: filtered[i], ref: ref)
                      .animate().fadeIn(delay: Duration(milliseconds: i * 25)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kg');
    final stockCtrl = TextEditingController(text: '0');
    final reorderCtrl = TextEditingController(text: '1');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Inventory Item'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name *')),
        const SizedBox(height: 12),
        TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit (kg, litre, piece...)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Stock'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: reorderCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reorder Level'))),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final profile = ref.read(authNotifierProvider).value;
            final supabase = ref.read(supabaseProvider);
            await supabase.from(SupabaseConstants.inventoryItems).insert({
              'id': const Uuid().v4(),
              'branch_id': profile?.branchId,
              'name': nameCtrl.text.trim(),
              'unit': unitCtrl.text.trim(),
              'current_stock': double.tryParse(stockCtrl.text) ?? 0,
              'reorder_level': double.tryParse(reorderCtrl.text) ?? 0,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            if (context.mounted) Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ));
  }
}

class _SChip extends StatelessWidget {
  final String label, value; final Color color;
  const _SChip(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text('$label: $value', style: GoogleFonts.outfit(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
  );
}

class _InventoryTile extends StatelessWidget {
  final InventoryItem item; final WidgetRef ref;
  const _InventoryTile({required this.item, required this.ref});

  Color get _color => item.isOut ? AppColors.error : item.isLow ? AppColors.warning : AppColors.success;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _color.withValues(alpha: 0.2))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.inventory_2_rounded, color: _color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text('Reorder at: ${item.reorderLevel} ${item.unit}', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${item.currentStock} ${item.unit}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: _color)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(item.isOut ? 'OUT' : item.isLow ? 'LOW' : 'OK', style: GoogleFonts.outfit(fontSize: 10, color: _color, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}
