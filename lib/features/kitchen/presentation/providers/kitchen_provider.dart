import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../orders/domain/entities/order_entities.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

// All pending/preparing KOTs (kitchen view)
final kitchenKotsProvider = StreamProvider<List<Kot>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();

  return supabase
      .from(SupabaseConstants.kots)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('created_at')
      .map((rows) => rows
          .map((r) => Kot(
                id: r['id'] as String,
                branchId: r['branch_id'] as String,
                sessionId: r['session_id'] as String,
                tableId: r['table_id'] as String,
                kotNumber: r['kot_number'] as String,
                status: r['status'] as String? ?? 'pending',
                waiterId: r['waiter_id'] as String?,
                waiterName: r['waiter_name'] as String?,
                items: const [],
                createdAt: DateTime.parse(r['created_at'] as String),
                notes: r['notes'] as String?,
              ))
          .where((k) => !k.isServed && !k.isCancelled)
          .toList());
});

// KOT items for a specific KOT - real-time stream
final kotItemsProvider = StreamProvider.family<List<KotItem>, String>((ref, kotId) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from(SupabaseConstants.kotItems)
      .stream(primaryKey: ['id'])
      .eq('kot_id', kotId)
      .order('id')
      .map((rows) => rows.map((r) => KotItem.fromJson(r)).toList());
});

// Kitchen status notifier
class KitchenNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  KitchenNotifier(this._ref) : super(const AsyncValue.data(null));

  SupabaseClient get _supabase => _ref.read(supabaseProvider);

  Future<void> updateKotStatus(String kotId, String newStatus) async {
    await _supabase
        .from(SupabaseConstants.kots)
        .update({
          'status': newStatus,
          if (newStatus == 'served') 'served_at': DateTime.now().toIso8601String(),
        })
        .eq('id', kotId);
    _ref.invalidate(kitchenKotsProvider);
    _ref.invalidate(kotItemsProvider(kotId));
    _ref.invalidate(dashboardKotsProvider);
  }
}

final kitchenNotifierProvider =
    StateNotifierProvider<KitchenNotifier, AsyncValue<void>>(
        (ref) => KitchenNotifier(ref));
