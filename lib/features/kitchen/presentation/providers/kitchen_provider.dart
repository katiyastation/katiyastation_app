// ============================================================
// KATIYA STATION RMS — KITCHEN PROVIDER
// Realtime KOT management via Socket.IO + REST API
// ============================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../orders/domain/entities/order_entities.dart';

// ── All active KOTs for this branch (REST fetch) ───────────
final kitchenKotsProvider = FutureProvider<List<Kot>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.kots,
    queryParameters: {
      'branchId': profile.branchId ?? '',
      'status': 'pending,preparing,ready',
      'sort': 'created_at:asc',
      'limit': '100',
    },
  );

  if (response.statusCode == 200) {
    final items = response.data as List<dynamic>? ?? [];
    return items.map((r) => Kot.fromJson(r as Map<String, dynamic>)).toList();
  }
  return [];
});

// ── KOT items for a specific KOT ──────────────────────────
final kotItemsProvider =
    FutureProvider.family<List<KotItem>, String>((ref, kotId) async {
  final response = await ApiClient.instance.get(
    ApiConstants.kotItems(kotId),
  );

  if (response.statusCode == 200) {
    final items = response.data as List<dynamic>? ?? [];
    return items
        .map((r) => KotItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }
  return [];
});

// ── Live KOT stream via Socket.IO ─────────────────────────
// Used to auto-refresh the kitchen screen on realtime events
final kitchenSocketStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final socket = SocketClient.instance;
  return socket.onKotNew().merge(socket.onKotStatusChanged());
});

// ── Kitchen Status Notifier ────────────────────────────────
class KitchenNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  KitchenNotifier(this._ref) : super(const AsyncValue.data(null));

  // ── Update KOT status (pending → preparing → ready → served) ──
  Future<void> updateKotStatus(String kotId, String newStatus) async {
    state = const AsyncValue.loading();
    try {
      final response = await ApiClient.instance.patch(
        ApiConstants.updateKotStatus(kotId),
        data: {
          'status': newStatus,
          if (newStatus == 'served')
            'servedAt': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        state = const AsyncValue.data(null);
        // Invalidate to refresh the list
        _ref.invalidate(kitchenKotsProvider);
      } else {
        state = AsyncValue.error(
          'Failed to update KOT status.',
          StackTrace.current,
        );
      }
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
    }
  }

  // ── Mark individual item as ready ─────────────────────────
  Future<void> updateItemStatus(
    String kotId,
    String itemId,
    String newStatus,
  ) async {
    try {
      await ApiClient.instance.patch(
        '${ApiConstants.kotItems(kotId)}/$itemId/status',
        data: {'status': newStatus},
      );
      _ref.invalidate(kotItemsProvider(kotId));
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
    }
  }

  // ── Cancel a KOT item ─────────────────────────────────────
  Future<void> cancelKotItem(String kotId, String itemId) async {
    await updateItemStatus(kotId, itemId, 'cancelled');
  }
}

final kitchenNotifierProvider =
    StateNotifierProvider<KitchenNotifier, AsyncValue<void>>(
  (ref) => KitchenNotifier(ref),
);

// ── Extension: merge two streams ──────────────────────────
extension StreamMerge<T> on Stream<T> {
  Stream<T> merge(Stream<T> other) async* {
    final controller = StreamController<T>.broadcast();
    listen(controller.add, onError: controller.addError);
    other.listen(controller.add, onError: controller.addError);
    yield* controller.stream;
  }
}
