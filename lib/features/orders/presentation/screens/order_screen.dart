import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../../domain/entities/order_entities.dart';

class OrderScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String sessionId;

  const OrderScreen({super.key, required this.tableId, required this.sessionId});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  String? _selectedCategoryId;
  final fmt = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final cart = ref.watch(orderNotifierProvider);
    final cartNotifier = ref.read(orderNotifierProvider.notifier);
    final categoriesAsync = profile?.branchId != null
        ? ref.watch(menuCategoriesProvider(profile!.branchId!))
        : const AsyncValue.data(<MenuCategory>[]);

    final subtotal = cartNotifier.subtotal;
    final tax = subtotal * 0.13;
    final total = subtotal + tax;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/tables'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Take Order'),
            Text('Session: ${widget.sessionId.substring(0, 8)}...',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          if (widget.sessionId.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text('Bill'),
              onPressed: () => context.go('/cashier?sessionId=${widget.sessionId}&tableId=${widget.tableId}'),
            ),
        ],
      ),
      body: Row(
        children: [
          // Left: Menu
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // Categories
                categoriesAsync.when(
                  loading: () => const SizedBox(height: 60, child: Center(child: LinearProgressIndicator())),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading menu: $e', style: const TextStyle(color: AppColors.error)),
                  ),
                  data: (categories) {
                    if (_selectedCategoryId == null && categories.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _selectedCategoryId = categories.first.id);
                      });
                    }
                    return Container(
                      height: 56,
                      color: AppColors.surface,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: categories.length,
                        itemBuilder: (ctx, i) {
                          final cat = categories[i];
                          final isSelected = cat.id == _selectedCategoryId;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedCategoryId = cat.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: Text(cat.name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  )),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                // Menu items
                Expanded(
                  child: _selectedCategoryId == null
                      ? const Center(child: Text('Select a category', style: TextStyle(color: AppColors.textSecondary)))
                      : _MenuItemsGrid(
                          categoryId: _selectedCategoryId!,
                          onAdd: (item) => cartNotifier.addItem(item),
                          cart: cart,
                        ),
                ),
              ],
            ),
          ),
          // Right: Cart + KOT history
          Container(
            width: 320,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Current Order',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const Spacer(),
                      if (cart.isNotEmpty)
                        TextButton(
                          onPressed: () => cartNotifier.clearCart(),
                          child: const Text('Clear', style: TextStyle(color: AppColors.error, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: cart.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_shopping_cart_rounded,
                                  size: 48, color: AppColors.textHint),
                              const SizedBox(height: 12),
                              Text('Add items from menu',
                                  style: GoogleFonts.outfit(color: AppColors.textHint, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: cart.length,
                          itemBuilder: (ctx, i) => _CartItemTile(
                            cartItem: cart[i],
                            onIncrease: () => cartNotifier.increaseQty(cart[i].item.id),
                            onDecrease: () => cartNotifier.decreaseQty(cart[i].item.id),
                            onRemove: () => cartNotifier.removeItem(cart[i].item.id),
                            fmt: fmt,
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 30)),
                        ),
                ),
                // Order summary + KOT button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow('Subtotal', 'NPR ${fmt.format(subtotal)}'),
                      const SizedBox(height: 4),
                      _SummaryRow('VAT (13%)', 'NPR ${fmt.format(tax)}'),
                      const Divider(height: 16),
                      _SummaryRow('Total', 'NPR ${fmt.format(total)}', isBold: true),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send KOT to Kitchen'),
                          onPressed: cart.isEmpty ? null : () => _sendKot(profile),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendKot(dynamic profile) async {
    if (profile == null) return;
    final kot = await ref.read(orderNotifierProvider.notifier).sendKot(
          sessionId: widget.sessionId,
          tableId: widget.tableId,
          branchId: profile.branchId ?? '',
        );
    if (kot != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 10),
              Text('${kot.kotNumber} sent to kitchen!'),
            ],
          ),
          backgroundColor: AppColors.surfaceVariant,
        ),
      );
    }
  }
}

class _MenuItemsGrid extends ConsumerWidget {
  final String categoryId;
  final void Function(MenuItem) onAdd;
  final List<CartItem> cart;

  const _MenuItemsGrid({required this.categoryId, required this.onAdd, required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsProvider(categoryId));
    final fmt = NumberFormat('#,##0');

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No items in this category', style: TextStyle(color: AppColors.textSecondary)))
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                final inCart = cart.where((c) => c.item.id == item.id).toList();
                final qty = inCart.isNotEmpty ? inCart.first.quantity : 0;
                return GestureDetector(
                  onTap: () => onAdd(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: qty > 0 ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: qty > 0 ? AppColors.primary : AppColors.border,
                        width: qty > 0 ? 1.5 : 0.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.restaurant_rounded, color: AppColors.textSecondary, size: 22),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                                  Text('NPR ${fmt.format(item.price)}',
                                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (qty > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: Text(qty.toString(),
                                  style: GoogleFonts.outfit(fontSize: 11, color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).scale(begin: const Offset(0.9, 0.9));
              },
            ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem cartItem;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final NumberFormat fmt;

  const _CartItemTile({
    required this.cartItem,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cartItem.item.name,
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                Text('NPR ${fmt.format(cartItem.total)}',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onDecrease,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.remove, size: 14, color: AppColors.textSecondary),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(cartItem.quantity.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              GestureDetector(
                onTap: onIncrease,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add, size: 14, color: AppColors.onPrimary),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 16, color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _SummaryRow(this.label, this.value, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 15 : 13,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            )),
        Text(value,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 16 : 13,
              color: isBold ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            )),
      ],
    );
  }
}
