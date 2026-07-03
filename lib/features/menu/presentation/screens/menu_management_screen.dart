import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../widgets/recipe_dialog.dart';
import 'package:file_picker/file_picker.dart';

// All categories for the branch
final menuCategoriesStreamProvider = FutureProvider<List<MenuCategory>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.menuCategories,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows.map((r) => MenuCategory.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

// Items by category
final menuItemsByCatProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, catId) async {
  final response = await ApiClient.instance.get(
    ApiConstants.menuItems,
    queryParameters: {'categoryId': catId},
  );
  final rows = response.data as List<dynamic>;
  return rows.map((r) => MenuItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

// All items across every category for the branch — used by menu search
final menuItemsAllProvider = FutureProvider<List<MenuItem>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.menuItems,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows.map((r) => MenuItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  ConsumerState<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  String? _selectedCatId;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(menuCategoriesStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menu Management'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('Bulk Import (Excel)'),
            onPressed: () => _importBulkExcel(context),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Category'),
            onPressed: () => _showCategoryDialog(context),
          ),
          const SizedBox(width: 8),
          if (_selectedCatId != null)
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Item'),
              onPressed: () => _showItemDialog(context),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: catsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cats) {
          if (cats.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.restaurant_menu_outlined, size: 64, color: AppColors.textHint),
              const SizedBox(height: 16),
              Text('No categories yet', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => _showCategoryDialog(context), child: const Text('Add First Category')),
            ]));
          }
          if (_selectedCatId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedCatId = cats.first.id);
            });
          }
          return Row(
            children: [
              // Sidebar - categories
              Container(
                width: 220,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(right: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Categories', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: cats.map((cat) {
                          final isSelected = cat.id == _selectedCatId;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedCatId = cat.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : null,
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected ? const Border(right: BorderSide(color: AppColors.primary, width: 3)) : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(cat.name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                                    Text(cat.type.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textHint)),
                                  ])),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                    onPressed: () => _deleteCategory(cat.id),
                                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              // Main content - search + items
              Expanded(
                child: Column(
                  children: [
                    _buildSearchBar(),
                    Expanded(
                      child: _searchQuery.trim().isNotEmpty
                          ? _SearchItemsGrid(
                              query: _searchQuery,
                              categories: cats,
                              onEdit: (item) => _showItemDialog(context, item),
                              onDelete: (id) => _deleteItem(id),
                            )
                          : (_selectedCatId == null
                              ? const Center(
                                  child: Text('Select a category', style: TextStyle(color: AppColors.textSecondary)))
                              : _ItemsGrid(
                                  catId: _selectedCatId!,
                                  onEdit: (item) => _showItemDialog(context, item),
                                  onDelete: (id) => _deleteItem(id),
                                )),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Search bar for filtering menu items by name, price, or category
  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search menu by name, price or category',
          hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Future<void> _showCategoryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    String type = 'food';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: StatefulBuilder(
          builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Category Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              onChanged: (v) => set(() => type = v!),
              items: const [
                DropdownMenuItem(value: 'food', child: Text('Food')),
                DropdownMenuItem(value: 'drink', child: Text('Drink')),
                DropdownMenuItem(value: 'bar', child: Text('Bar')),
              ],
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                final profile = ref.read(authNotifierProvider).value;
                if (profile?.branchId == null) {
                  throw Exception('Branch ID not found in user profile. Cannot add category.');
                }
                await ApiClient.instance.post(
                  ApiConstants.menuCategories,
                  data: {
                    'branchId': profile!.branchId,
                    'name': nameCtrl.text.trim(),
                    'type': type,
                  },
                );
                ref.invalidate(menuCategoriesStreamProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showItemDialog(BuildContext context, [MenuItem? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final imageUrlCtrl = TextEditingController(text: existing?.imageUrl ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Menu Item' : 'Edit Item'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name *')),
            const SizedBox(height: 12),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (NPR) *')),
            const SizedBox(height: 12),
            TextField(controller: imageUrlCtrl, decoration: const InputDecoration(labelText: 'Image URL (paste image link)', prefixIcon: Icon(Icons.image_outlined, size: 18))),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                final profile = ref.read(authNotifierProvider).value;
                if (profile?.branchId == null) {
                  throw Exception('Branch ID not found in user profile. Cannot save item.');
                }
                final targetCatId = existing?.categoryId ?? _selectedCatId;
                final data = {
                  'branchId': profile!.branchId,
                  'categoryId': targetCatId,
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text) ?? 0,
                  'imageUrl': imageUrlCtrl.text.trim().isEmpty ? null : imageUrlCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'isAvailable': existing?.isAvailable ?? true,
                };
                if (existing == null) {
                  await ApiClient.instance.post(ApiConstants.menuItems, data: data);
                } else {
                  await ApiClient.instance.patch(ApiConstants.menuItemById(existing.id), data: data);
                }
                if (targetCatId != null) {
                  ref.invalidate(menuItemsByCatProvider(targetCatId));
                }
                ref.invalidate(menuItemsAllProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBulkExcel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        throw Exception('Failed to read file bytes. Make sure the file is not empty.');
      }

      final profile = ref.read(authNotifierProvider).value;
      final branchId = profile?.branchId;
      if (branchId == null) {
        throw Exception('Branch ID not found in user profile.');
      }

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Importing menu items... Please wait.'),
                ],
              ),
            ),
          ),
        ),
      );

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: result.files.first.name,
        ),
      });

      final response = await ApiClient.instance.upload(
        '${ApiConstants.menuImportExcel}?branchId=$branchId',
        formData,
      );
      final resultData = response.data as Map<String, dynamic>;
      final created = resultData['created'] as int? ?? 0;

      if (context.mounted) Navigator.pop(context);

      ref.invalidate(menuCategoriesStreamProvider);
      if (_selectedCatId != null) {
        ref.invalidate(menuItemsByCatProvider(_selectedCatId!));
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ Imported $created menu items!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name != null);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to import: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteCategory(String id) async {
    await ApiClient.instance.delete(ApiConstants.menuCategoryById(id));
    ref.invalidate(menuCategoriesStreamProvider);
    if (_selectedCatId == id) setState(() => _selectedCatId = null);
  }

  Future<void> _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Menu Item'),
        content: const Text('Are you sure you want to delete this menu item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiClient.instance.delete(ApiConstants.menuItemById(id));
    if (_selectedCatId != null) {
      ref.invalidate(menuItemsByCatProvider(_selectedCatId!));
    }
    ref.invalidate(menuItemsAllProvider);
  }
}

class _ItemsGrid extends ConsumerWidget {
  final String catId;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<String> onDelete;
  const _ItemsGrid({required this.catId, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsByCatProvider(catId));
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) => items.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.no_food_rounded, size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('No items in this category', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ]))
          : _ItemsGridView(items: items, ref: ref, onEdit: onEdit, onDelete: onDelete),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Search results across every category — filters by name, price, or category
// ════════════════════════════════════════════════════════════════════════════
class _SearchItemsGrid extends ConsumerWidget {
  final String query;
  final List<MenuCategory> categories;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<String> onDelete;
  const _SearchItemsGrid({
    required this.query,
    required this.categories,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsAllProvider);
    final q = query.trim().toLowerCase();

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final catNameById = {for (final c in categories) c.id: c.name.toLowerCase()};
        final filtered = items.where((item) {
          final nameMatch = item.name.toLowerCase().contains(q);
          final categoryMatch = (catNameById[item.categoryId] ?? '').contains(q);
          final priceMatch =
              item.price.toStringAsFixed(0).contains(q) || item.price.toStringAsFixed(2).contains(q);
          return nameMatch || categoryMatch || priceMatch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.search_off_rounded, size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('No items match "$query"', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ]),
          );
        }
        return _ItemsGridView(items: filtered, ref: ref, onEdit: onEdit, onDelete: onDelete);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared grid layout for a resolved list of menu items
// ════════════════════════════════════════════════════════════════════════════
class _ItemsGridView extends StatelessWidget {
  final List<MenuItem> items;
  final WidgetRef ref;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<String> onDelete;
  const _ItemsGridView({required this.items, required this.ref, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.responsiveValue(mobile: 180, tablet: 210, desktop: 240),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _MenuItemCard(
        item: items[i],
        ref: ref,
        onEdit: () => onEdit(items[i]),
        onDelete: () => onDelete(items[i].id),
      ).animate().fadeIn(delay: Duration(milliseconds: i * 30)).scale(begin: const Offset(0.95, 0.95)),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final WidgetRef ref;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _MenuItemCard({
    required this.item,
    required this.ref,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.isAvailable ? AppColors.border : AppColors.error.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1.35,
                child: hasImage
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (val) {
                      if (val == 'edit') {
                        onEdit();
                      } else if (val == 'recipe') {
                        showDialog(
                          context: context,
                          builder: (ctx) => RecipeDialog(item: item),
                        );
                      } else if (val == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'recipe', child: Text('Recipe')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.name,
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('NPR ${fmt.format(item.price)}',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (item.isAvailable ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.isAvailable ? 'Available' : 'Off', style: GoogleFonts.outfit(fontSize: 10, color: item.isAvailable ? AppColors.success : AppColors.error)),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await ApiClient.instance.patch(
                          ApiConstants.menuItemById(item.id),
                          data: {'isAvailable': !item.isAvailable},
                        );
                        ref.invalidate(menuItemsByCatProvider(item.categoryId));
                        ref.invalidate(menuItemsAllProvider);
                      },
                      child: Icon(item.isAvailable ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                          color: item.isAvailable ? AppColors.success : AppColors.textHint, size: 22),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.restaurant_menu_rounded, color: AppColors.primary, size: 26)),
    );
  }
}
