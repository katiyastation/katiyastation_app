import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/table_entities.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

// ─── All tables stream (real-time) ────────────────────────────────────────
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

// ─── Active sessions stream ────────────────────────────────────────────────
final activeSessionsStreamProvider =
    StreamProvider<List<TableSession>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();

  return supabase
      .from(SupabaseConstants.tableSessions)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('opened_at')
      .map((rows) => rows
          .where((r) => (r['status'] as String?) == 'open')
          .map((r) => TableSession.fromJson(r))
          .toList());
});

// ─── Session for a specific table ─────────────────────────────────────────
final tableSessionProvider =
    FutureProvider.family<TableSession?, String>((ref, tableId) async {
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

// ─── Reservations stream ───────────────────────────────────────────────────
final reservationsStreamProvider =
    StreamProvider<List<TableReservation>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();

  return supabase
      .from(SupabaseConstants.reservations)
      .stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '')
      .order('reservation_time')
      .map((rows) =>
          rows.map((r) => TableReservation.fromJson(r)).toList());
});

// ─── Table Notifier ────────────────────────────────────────────────────────
class TableNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  TableNotifier(this._ref) : super(const AsyncValue.data(null));

  SupabaseClient get _supabase => _ref.read(supabaseProvider);
  String? get _branchId => _ref.read(authNotifierProvider).value?.branchId;

  void _invalidateAll(String tableId) {
    _ref.invalidate(tablesStreamProvider);
    _ref.invalidate(tableSessionProvider(tableId));
    _ref.invalidate(activeSessionsStreamProvider);
    _ref.invalidate(dashboardSessionsProvider);
  }

  // ── Open Session ────────────────────────────────────────────────────────
  Future<TableSession?> openSession(String tableId,
      {int guestCount = 1, String? notes}) async {
    state = const AsyncValue.loading();
    try {
      final profile = _ref.read(authNotifierProvider).value!;
      final count = await _supabase
          .from(SupabaseConstants.tableSessions)
          .select('id')
          .eq('branch_id', _branchId ?? '');
      final sessionNum =
          'TS-${(count.length + 1).toString().padLeft(4, '0')}';

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
            if (notes != null) 'notes': notes,
          })
          .select()
          .single();

      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'status': 'occupied',
        'current_session_id': sessionData['id'],
        'bill_requested': false,
        'bill_requested_at': null,
      }).eq('id', tableId);

      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return TableSession.fromJson(sessionData);
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return null;
    }
  }

  // ── Request Bill ────────────────────────────────────────────────────────
  Future<bool> requestBill(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from(SupabaseConstants.tableSessions).update({
        'bill_requested': true,
        'bill_requested_at': now,
      }).eq('id', sessionId);

      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'status': 'ready_for_billing',
        'bill_requested': true,
        'bill_requested_at': now,
      }).eq('id', tableId);

      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Close Session / Free Table ──────────────────────────────────────────
  Future<bool> closeSession(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      await _supabase.from(SupabaseConstants.tableSessions).update({
        'status': 'closed',
        'closed_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);

      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'status': 'available',
        'current_session_id': null,
        'bill_requested': false,
        'bill_requested_at': null,
      }).eq('id', tableId);

      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Add Table ───────────────────────────────────────────────────────────
  Future<bool> addTable({
    required String tableNumber,
    required String section,
    required int capacity,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      if (_branchId == null) {
        throw Exception('Branch ID not found. Cannot add table.');
      }
      await _supabase.from(SupabaseConstants.restaurantTables).insert({
        'id': const Uuid().v4(),
        'branch_id': _branchId,
        'table_number': tableNumber,
        'section': section,
        'capacity': capacity,
        'status': 'available',
        'bill_requested': false,
        'is_enabled': true,
        if (description != null && description.isNotEmpty)
          'description': description,
      });
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Edit Table ──────────────────────────────────────────────────────────
  Future<bool> editTable({
    required String tableId,
    required String tableNumber,
    required String section,
    required int capacity,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'table_number': tableNumber,
        'section': section,
        'capacity': capacity,
        if (description != null) 'description': description,
      }).eq('id', tableId);
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Delete Table ────────────────────────────────────────────────────────
  Future<bool> deleteTable(String tableId) async {
    state = const AsyncValue.loading();
    try {
      await _supabase
          .from(SupabaseConstants.restaurantTables)
          .delete()
          .eq('id', tableId);
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Enable / Disable Table ──────────────────────────────────────────────
  Future<bool> setTableEnabled(String tableId, bool enabled) async {
    state = const AsyncValue.loading();
    try {
      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'is_enabled': enabled,
        'status': enabled ? 'available' : 'closed',
      }).eq('id', tableId);
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Transfer Session (move to another table) ────────────────────────────
  Future<bool> transferSession({
    required String fromTableId,
    required String toTableId,
    required String sessionId,
  }) async {
    state = const AsyncValue.loading();
    try {
      // Update session table_id
      await _supabase.from(SupabaseConstants.tableSessions).update({
        'table_id': toTableId,
      }).eq('id', sessionId);

      // Free old table
      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'status': 'available',
        'current_session_id': null,
        'bill_requested': false,
        'bill_requested_at': null,
      }).eq('id', fromTableId);

      // Occupy new table
      await _supabase.from(SupabaseConstants.restaurantTables).update({
        'status': 'occupied',
        'current_session_id': sessionId,
      }).eq('id', toTableId);

      _ref.invalidate(tablesStreamProvider);
      _ref.invalidate(tableSessionProvider(fromTableId));
      _ref.invalidate(tableSessionProvider(toTableId));
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(dashboardSessionsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Update table status ─────────────────────────────────────────────────
  Future<void> updateTableStatus(String tableId, String status) async {
    await _supabase.from(SupabaseConstants.restaurantTables).update({
      'status': status,
      if (status == 'available') 'bill_requested': false,
      if (status == 'available') 'bill_requested_at': null,
    }).eq('id', tableId);
    _invalidateAll(tableId);
  }
}

final tableNotifierProvider =
    StateNotifierProvider<TableNotifier, AsyncValue<void>>(
  (ref) => TableNotifier(ref),
);

// ─── Reservation Notifier ──────────────────────────────────────────────────
class ReservationNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ReservationNotifier(this._ref) : super(const AsyncValue.data(null));

  SupabaseClient get _supabase => _ref.read(supabaseProvider);
  String? get _branchId => _ref.read(authNotifierProvider).value?.branchId;

  Future<bool> addReservation({
    required String customerName,
    String? customerPhone,
    required int guestCount,
    required DateTime reservationTime,
    String? tableId,
    String? notes,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _supabase.from(SupabaseConstants.reservations).insert({
        'id': const Uuid().v4(),
        'branch_id': _branchId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'guest_count': guestCount,
        'reservation_time': reservationTime.toIso8601String(),
        'table_id': tableId,
        'status': 'confirmed',
        'notes': notes,
      });
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> updateReservation({
    required String id,
    required String customerName,
    String? customerPhone,
    required int guestCount,
    required DateTime reservationTime,
    String? tableId,
    String? notes,
    String? status,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _supabase.from(SupabaseConstants.reservations).update({
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'guest_count': guestCount,
        'reservation_time': reservationTime.toIso8601String(),
        'table_id': tableId,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
      }).eq('id', id);
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> cancelReservation(String id) async {
    state = const AsyncValue.loading();
    try {
      await _supabase
          .from(SupabaseConstants.reservations)
          .update({'status': 'cancelled'}).eq('id', id);
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> markNoShow(String id) async {
    state = const AsyncValue.loading();
    try {
      await _supabase
          .from(SupabaseConstants.reservations)
          .update({'status': 'no_show'}).eq('id', id);
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }
}

final reservationNotifierProvider =
    StateNotifierProvider<ReservationNotifier, AsyncValue<void>>(
  (ref) => ReservationNotifier(ref),
);
