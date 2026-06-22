import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/table_entities.dart';

// All tables stream
final tablesStreamProvider = StreamProvider<List<RestaurantTable>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();

  return supabase
      .from(SupabaseConstants.restaurantTables)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('table_number')
      .map((rows) => rows.map((r) => RestaurantTable.fromJson(r)).toList());
});

// Session for a specific table
final tableSessionProvider = FutureProvider.family<TableSession?, String>((ref, tableId) async {
  final supabase = ref.watch(supabaseProvider);
  final data = await supabase
      .from(SupabaseConstants.tableSessions)
      .select()
      .eq('table_id', tableId)
      .eq('status', 'open')
      .maybeSingle();
  if (data == null) return null;
  return TableSession.fromJson(data);
});

// Table notifier for CRUD
class TableNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  TableNotifier(this._ref) : super(const AsyncValue.data(null));

  SupabaseClient get _supabase => _ref.read(supabaseProvider);
  String? get _branchId => _ref.read(authNotifierProvider).value?.branchId;

  Future<TableSession?> openSession(String tableId, {int guestCount = 1}) async {
    state = const AsyncValue.loading();
    try {
      final profile = _ref.read(authNotifierProvider).value!;
      // Get next session number
      final count = await _supabase
          .from(SupabaseConstants.tableSessions)
          .select('id')
          .eq('branch_id', _branchId ?? '');
      final sessionNum = 'TS-${(count.length + 1).toString().padLeft(4, '0')}';

      final sessionData = await _supabase
          .from(SupabaseConstants.tableSessions)
          .insert({
            'id': const Uuid().v4(),
            'table_id': tableId,
            'branch_id': _branchId,
            'session_number': sessionNum,
            'status': 'open',
            'waiter_id': profile.id,
            'guest_count': guestCount,
            'total_amount': 0,
            'opened_at': DateTime.now().toIso8601String(),
            'bill_requested': false,
            'bill_requested_at': null,
          })
          .select()
          .single();

      await _supabase
          .from(SupabaseConstants.restaurantTables)
          .update({
            'status': 'occupied',
            'current_session_id': sessionData['id'],
            'bill_requested': false,
            'bill_requested_at': null,
          })
          .eq('id', tableId);

      state = const AsyncValue.data(null);
      return TableSession.fromJson(sessionData);
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return null;
    }
  }

  Future<bool> requestBill(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase
          .from(SupabaseConstants.tableSessions)
          .update({
            'bill_requested': true,
            'bill_requested_at': now,
          })
          .eq('id', sessionId);

      await _supabase
          .from(SupabaseConstants.restaurantTables)
          .update({
            'bill_requested': true,
            'bill_requested_at': now,
          })
          .eq('id', tableId);

      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> addTable(String tableNumber, String section, int capacity) async {
    state = const AsyncValue.loading();
    try {
      if (_branchId == null) {
        throw Exception('Branch ID not found in user profile. Cannot add table.');
      }
      final id = const Uuid().v4();
      await _supabase.from(SupabaseConstants.restaurantTables).insert({
        'id': id,
        'branch_id': _branchId,
        'table_number': tableNumber,
        'section': section,
        'capacity': capacity,
        'status': 'available',
        'bill_requested': false,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<void> updateTableStatus(String tableId, String status) async {
    await _supabase
        .from(SupabaseConstants.restaurantTables)
        .update({
          'status': status,
          if (status == 'available') 'bill_requested': false,
          if (status == 'available') 'bill_requested_at': null,
        }).eq('id', tableId);
  }
}

final tableNotifierProvider = StateNotifierProvider<TableNotifier, AsyncValue<void>>(
  (ref) => TableNotifier(ref),
);
