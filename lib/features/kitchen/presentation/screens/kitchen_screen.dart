import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/kitchen_provider.dart';
import '../../../orders/domain/entities/order_entities.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kotsAsync = ref.watch(kitchenKotsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kitchen Display System'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: kotsAsync.when(
              data: (kots) => Text(
                '${kots.length} Active KOTs',
                style: GoogleFonts.outfit(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const SizedBox(),
            ),
          ),
        ],
      ),
      body: kotsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
        data: (kots) {
          if (kots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Lottie.network(
                    'https://assets9.lottiefiles.com/packages/lf20_touohxv0.json',
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 80,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    'All caught up!',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
                  const SizedBox(height: 8),
                  Text(
                    'No pending kitchen orders',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 15),
                  ).animate().fadeIn(delay: 350.ms),
                ],
              ),
            );
          }

          final pending = kots.where((k) => k.isPending).toList();
          final preparing = kots.where((k) => k.isPreparing).toList();
          final ready = kots.where((k) => k.isReady).toList();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending column
              _KanbanColumn(
                title: 'Pending',
                icon: Icons.hourglass_empty_rounded,
                color: AppColors.warning,
                kots: pending,
                nextStatus: 'preparing',
                nextLabel: 'Start Preparing',
                ref: ref,
              ),
              // Preparing column
              _KanbanColumn(
                title: 'Preparing',
                icon: Icons.whatshot_rounded,
                color: AppColors.info,
                kots: preparing,
                nextStatus: 'ready',
                nextLabel: 'Mark Ready',
                ref: ref,
              ),
              // Ready column
              _KanbanColumn(
                title: 'Ready to Serve',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                kots: ready,
                nextStatus: 'served',
                nextLabel: 'Mark Served',
                ref: ref,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Kot> kots;
  final String nextStatus;
  final String nextLabel;
  final WidgetRef ref;

  const _KanbanColumn({
    required this.title,
    required this.icon,
    required this.color,
    required this.kots,
    required this.nextStatus,
    required this.nextLabel,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(title,
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(kots.length.toString(),
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: kots.length,
                itemBuilder: (ctx, i) => _KotCard(
                  kot: kots[i],
                  nextStatus: nextStatus,
                  nextLabel: nextLabel,
                  color: color,
                  ref: ref,
                ).animate().fadeIn(delay: Duration(milliseconds: i * 50)).slideX(begin: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KotCard extends ConsumerWidget {
  final Kot kot;
  final String nextStatus;
  final String nextLabel;
  final Color color;
  final WidgetRef ref;

  const _KotCard({
    required this.kot,
    required this.nextStatus,
    required this.nextLabel,
    required this.color,
    required this.ref,
  });

  String _elapsedLabel() {
    final mins = kot.elapsed.inMinutes;
    if (mins < 1) return 'Just now';
    return '${mins}m ago';
  }

  Color _elapsedColor() {
    final mins = kot.elapsed.inMinutes;
    if (mins < 10) return AppColors.success;
    if (mins < 20) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(kotItemsProvider(kot.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(kot.kotNumber,
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                const Icon(Icons.table_restaurant_rounded, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Expanded(child: Text(kot.tableId.substring(0, 8),
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _elapsedColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_elapsedLabel(),
                      style: GoogleFonts.outfit(fontSize: 10, color: _elapsedColor(), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          // Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: itemsAsync.when(
              loading: () => Skeletonizer(
                enabled: true,
                effect: const ShimmerEffect(
                  baseColor: AppColors.surfaceVariant,
                  highlightColor: AppColors.surface,
                ),
                child: Column(
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Container(width: 24, height: 24, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(6))),
                      const SizedBox(width: 8),
                      Container(height: 13, width: 120, color: AppColors.surfaceVariant),
                    ]),
                  )),
                ),
              ),
              error: (e, _) => const Text('Error loading items', style: TextStyle(color: AppColors.error, fontSize: 12)),
              data: (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text('×${item.quantity}',
                            style: GoogleFonts.outfit(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.menuItemName,
                          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary))),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
          if (kot.notes != null && kot.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('📝 ${kot.notes}',
                    style: GoogleFonts.outfit(fontSize: 11, color: AppColors.warning)),
              ),
            ),
          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => ref.read(kitchenNotifierProvider.notifier)
                    .updateKotStatus(kot.id, nextStatus),
                child: Text(nextLabel, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
