import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../../domain/entities/order_entities.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

// Menu categories for ordering (by branchId)
final menuCategoriesProvider = StreamProvider.family<List<MenuCategory>, String>((ref, branchId) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from(SupabaseConstants.menuCategories)
      .stream(primaryKey: ['id'])
      .eq('branch_id', branchId)
      .order('sort_order')
      .map((rows) => rows
          .map((r) => MenuCategory.fromJson(r))
          .where((c) => c.isActive)
          .toList());
});

// Menu items for ordering (by categoryId)
final menuItemsProvider = StreamProvider.family<List<MenuItem>, String>((ref, categoryId) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from(SupabaseConstants.menuItems)
      .stream(primaryKey: ['id'])
      .eq('category_id', categoryId)
      .order('name')
      .map((rows) => rows
          .map((r) => MenuItem.fromJson(r))
          .where((i) => i.isAvailable)
          .toList());
});

// KOTs for a session
final sessionKotsProvider = StreamProvider.family<List<Kot>, String>((ref, sessionId) {
  final supabase = ref.watch(supabaseProvider);
  if (sessionId.isEmpty) return const Stream.empty();
  return supabase
      .from(SupabaseConstants.kots)
      .stream(primaryKey: ['id'])
      .eq('session_id', sessionId)
      .order('created_at')
      .map((rows) => rows
          .map((r) {
            // items are joined separately
            return Kot(
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
            );
          })
          .toList());
});

// Cart state for current order
class CartItem {
  final MenuItem item;
  int quantity;
  String? notes;

  CartItem({required this.item, this.quantity = 1, this.notes});

  double get total => item.price * quantity;
}

class OrderNotifier extends StateNotifier<List<CartItem>> {
  final Ref _ref;
  OrderNotifier(this._ref) : super([]);

  void addItem(MenuItem item) {
    final existing = state.where((c) => c.item.id == item.id).toList();
    if (existing.isNotEmpty) {
      state = state.map((c) => c.item.id == item.id
          ? (CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes))
          : c).toList();
    } else {
      state = [...state, CartItem(item: item)];
    }
  }

  void removeItem(String itemId) {
    state = state.where((c) => c.item.id != itemId).toList();
  }

  void increaseQty(String itemId) {
    state = state.map((c) => c.item.id == itemId
        ? CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes)
        : c).toList();
  }

  void decreaseQty(String itemId) {
    state = state.map((c) {
      if (c.item.id == itemId) {
        if (c.quantity <= 1) return null;
        return CartItem(item: c.item, quantity: c.quantity - 1, notes: c.notes);
      }
      return c;
    }).whereType<CartItem>().toList();
  }

  void clearCart() => state = [];

  double get subtotal => state.fold(0, (sum, c) => sum + c.total);

  Future<Kot?> sendKot({
    required String sessionId,
    required String tableId,
    required String branchId,
    String? notes,
  }) async {
    if (state.isEmpty) return null;
    final supabase = _ref.read(supabaseProvider);
    final profile = _ref.read(authNotifierProvider).value;

    // Get KOT number
    final kotCount = await supabase
        .from(SupabaseConstants.kots)
        .select('id')
        .eq('branch_id', branchId);
    final kotNumber = 'KOT-${(kotCount.length + 1).toString().padLeft(3, '0')}';
    final kotId = const Uuid().v4();

    await supabase.from(SupabaseConstants.kots).insert({
      'id': kotId,
      'branch_id': branchId,
      'session_id': sessionId,
      'table_id': tableId,
      'kot_number': kotNumber,
      'status': 'pending',
      'waiter_id': profile?.id,
      'waiter_name': profile?.fullName,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Insert KOT items
    double newKotSubtotal = 0.0;
    for (final cartItem in state) {
      newKotSubtotal += cartItem.item.price * cartItem.quantity;
      await supabase.from(SupabaseConstants.kotItems).insert({
        'id': const Uuid().v4(),
        'kot_id': kotId,
        'menu_item_id': cartItem.item.id,
        'name': cartItem.item.name,
        'quantity': cartItem.quantity,
        'unit_price': cartItem.item.price,
        'note': cartItem.notes,
      });
    }

    // Update session total in database
    try {
      final sessionRes = await supabase
          .from(SupabaseConstants.tableSessions)
          .select('total_amount')
          .eq('id', sessionId)
          .maybeSingle();
      if (sessionRes != null) {
        final currentTotal = (sessionRes['total_amount'] as num?)?.toDouble() ?? 0.0;
        await supabase
            .from(SupabaseConstants.tableSessions)
            .update({'total_amount': currentTotal + newKotSubtotal})
            .eq('id', sessionId);
      }
    } catch (_) {}

    // Update session total
    final kotItems = state.map((c) => KotItem(
      id: '', kotId: kotId,
      menuItemId: c.item.id,
      menuItemName: c.item.name,
      quantity: c.quantity,
      unitPrice: c.item.price,
    )).toList();

    _ref.invalidate(sessionKotsProvider(sessionId));
    _ref.invalidate(tableSessionProvider(tableId));
    _ref.invalidate(dashboardKotsProvider);
    _ref.invalidate(dashboardSessionsProvider);

    clearCart();
    return Kot(
      id: kotId,
      branchId: branchId,
      sessionId: sessionId,
      tableId: tableId,
      kotNumber: kotNumber,
      status: 'pending',
      waiterId: profile?.id,
      waiterName: profile?.fullName,
      items: kotItems,
      createdAt: DateTime.now(),
      notes: notes,
    );
  }
}

final orderNotifierProvider = StateNotifierProvider<OrderNotifier, List<CartItem>>(
  (ref) => OrderNotifier(ref),
);
