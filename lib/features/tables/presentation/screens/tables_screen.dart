import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/tables_provider.dart';
import '../../domain/entities/table_entities.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  String _selectedSection = 'All';

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesStreamProvider);
    final profile = ref.watch(authNotifierProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tables'),
        actions: [
          if (profile?.isBranchManager == true || profile?.isCashier == true)
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Table'),
              onPressed: () => _showAddTableDialog(context),
            ),
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
        data: (tables) {
          final sections = ['All', ...{...tables.map((t) => t.section)}];
          final filtered = _selectedSection == 'All'
              ? tables
              : tables.where((t) => t.section == _selectedSection).toList();

          final available = tables.where((t) => t.isAvailable).length;
          final occupied = tables.where((t) => t.isOccupied).length;
          final reserved = tables.where((t) => t.isReserved).length;

          return Column(
            children: [
              // Status summary
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    _StatusChip('Available', available, AppColors.tableAvailable),
                    const SizedBox(width: 12),
                    _StatusChip('Occupied', occupied, AppColors.tableOccupied),
                    const SizedBox(width: 12),
                    _StatusChip('Reserved', reserved, AppColors.tableReserved),
                  ],
                ),
              ),
              // Section filter
              if (sections.length > 2)
                Container(
                  height: 48,
                  color: AppColors.surface,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: sections.length,
                    itemBuilder: (ctx, i) {
                      final sec = sections[i];
                      final isSelected = sec == _selectedSection;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSection = sec),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: Text(sec,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              )),
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.table_restaurant_outlined,
                                size: 64, color: AppColors.textSecondary),
                            const SizedBox(height: 16),
                            Text('No tables found',
                                style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            if (profile?.isBranchManager == true)
                              ElevatedButton(
                                onPressed: () => _showAddTableDialog(context),
                                child: const Text('Add First Table'),
                              ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _TableCard(
                          table: filtered[i],
                          onTap: () => _handleTableTap(context, filtered[i]),
                        ).animate().fadeIn(delay: Duration(milliseconds: i * 40)).scale(begin: const Offset(0.9, 0.9)),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleTableTap(BuildContext context, RestaurantTable table) async {
    if (table.isAvailable) {
      // Ask to open session
      final guestCount = await _showGuestCountDialog(context);
      if (guestCount == null || !context.mounted) return;
      final session = await ref.read(tableNotifierProvider.notifier)
          .openSession(table.id, guestCount: guestCount);
      if (session != null && context.mounted) {
        context.go('/tables/${table.id}/order?sessionId=${session.id}');
      }
    } else if (table.isOccupied) {
      // Go to existing order
      final sessionAsync = ref.read(tableSessionProvider(table.id));
      sessionAsync.when(
        data: (session) {
          if (session != null && context.mounted) {
            context.go('/tables/${table.id}/order?sessionId=${session.id}');
          }
        },
        loading: () {},
        error: (_, __) {},
      );
      // Refresh and navigate
      final session = await ref.read(supabaseProvider)
          .from(SupabaseConstants.tableSessions)
          .select()
          .eq('table_id', table.id)
          .eq('status', 'open')
          .maybeSingle();
      if (session != null && context.mounted) {
        context.go('/tables/${table.id}/order?sessionId=${session['id']}');
      }
    }
  }

  Future<int?> _showGuestCountDialog(BuildContext context) async {
    int guests = 2;
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Table Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How many guests?', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (ctx, setLocal) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => setLocal(() { if (guests > 1) guests--; }),
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                  ),
                  Container(
                    width: 60,
                    alignment: Alignment.center,
                    child: Text(guests.toString(),
                        style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    onPressed: () => setLocal(() { guests++; }),
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, guests), child: const Text('Open')),
        ],
      ),
    );
  }

  void _showAddTableDialog(BuildContext context) {
    final numCtrl = TextEditingController();
    final sectionCtrl = TextEditingController(text: 'Main');
    int capacity = 4;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Table'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numCtrl,
                decoration: const InputDecoration(labelText: 'Table Number (e.g. A-01)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sectionCtrl,
                decoration: const InputDecoration(labelText: 'Section'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Capacity:', style: TextStyle(color: AppColors.textSecondary)),
                  const Spacer(),
                  IconButton(onPressed: () => setLocal(() { if (capacity > 1) capacity--; }), icon: const Icon(Icons.remove)),
                  Text(capacity.toString(), style: const TextStyle(fontSize: 18)),
                  IconButton(onPressed: () => setLocal(() { capacity++; }), icon: const Icon(Icons.add)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (numCtrl.text.trim().isEmpty) return;
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final success = await ref.read(tableNotifierProvider.notifier)
                  .addTable(numCtrl.text.trim(), sectionCtrl.text.trim(), capacity);
              if (ctx.mounted) {
                if (success) {
                  Navigator.pop(ctx);
                } else {
                  final state = ref.read(tableNotifierProvider);
                  state.whenOrNull(
                    error: (err, _) => scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Error: $err'),
                        backgroundColor: AppColors.error,
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatusChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$count $label', style: GoogleFonts.outfit(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final RestaurantTable table;
  final VoidCallback onTap;

  const _TableCard({required this.table, required this.onTap});

  Color get _statusColor {
    if (table.isAvailable) return AppColors.tableAvailable;
    if (table.isOccupied) return AppColors.tableOccupied;
    if (table.isReserved) return AppColors.tableReserved;
    return AppColors.tableCleaning;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.table_restaurant_rounded, color: _statusColor, size: 28),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(table.tableNumber,
                          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text(table.section,
                          style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          table.status.toUpperCase(),
                          style: GoogleFonts.outfit(fontSize: 9, color: _statusColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Row(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 12, color: AppColors.textHint),
                  const SizedBox(width: 2),
                  Text('${table.capacity}', style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
