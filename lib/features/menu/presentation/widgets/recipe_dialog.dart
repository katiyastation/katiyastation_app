import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/menu_entities.dart';

final recipeIngredientsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, menuItemId) async {
  final supabase = ref.watch(supabaseProvider);
  
  // First, get the recipe row
  final recipe = await supabase
      .from(SupabaseConstants.recipes)
      .select()
      .eq('menu_item_id', menuItemId)
      .maybeSingle();

  if (recipe == null) return [];

  final recipeId = recipe['id'] as String;

  // Now, fetch all ingredients for this recipe
  final data = await supabase
      .from(SupabaseConstants.recipeIngredients)
      .select('*, inventory_items(name, unit)')
      .eq('recipe_id', recipeId);

  return List<Map<String, dynamic>>.from(data);
});

class RecipeDialog extends ConsumerStatefulWidget {
  final MenuItem item;
  const RecipeDialog({super.key, required this.item});

  @override
  ConsumerState<RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends ConsumerState<RecipeDialog> {
  bool _loading = false;
  String? _recipeId;
  final _instructionsCtrl = TextEditingController();
  List<Map<String, dynamic>> _ingredients = [];

  // Dropdown options
  List<Map<String, dynamic>> _allInventoryItems = [];
  String? _selectedInventoryItemId;
  final _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecipeAndIngredients();
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecipeAndIngredients() async {
    setState(() => _loading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final profile = ref.read(authNotifierProvider).value;

      // 1. Fetch all inventory items for branch
      final invData = await supabase
          .from(SupabaseConstants.inventoryItems)
          .select('id, name, unit')
          .eq('branch_id', profile?.branchId ?? '');
      _allInventoryItems = List<Map<String, dynamic>>.from(invData);

      // 2. Fetch recipe
      final recipe = await supabase
          .from(SupabaseConstants.recipes)
          .select()
          .eq('menu_item_id', widget.item.id)
          .maybeSingle();

      if (recipe != null) {
        _recipeId = recipe['id'] as String;
        _instructionsCtrl.text = recipe['instructions'] as String? ?? '';

        // 3. Fetch ingredients
        final ingData = await supabase
            .from(SupabaseConstants.recipeIngredients)
            .select('*, inventory_items(name, unit)')
            .eq('recipe_id', _recipeId!);
        _ingredients = List<Map<String, dynamic>>.from(ingData);
      }
    } catch (e) {
      debugPrint('Error loading recipe: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createRecipe() async {
    setState(() => _loading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final profile = ref.read(authNotifierProvider).value;
      final newId = const Uuid().v4();

      await supabase.from(SupabaseConstants.recipes).insert({
        'id': newId,
        'menu_item_id': widget.item.id,
        'branch_id': profile?.branchId,
        'instructions': '',
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() {
        _recipeId = newId;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create recipe: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addIngredient() async {
    if (_selectedInventoryItemId == null || _qtyCtrl.text.isEmpty) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;

    setState(() => _loading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      await supabase.from(SupabaseConstants.recipeIngredients).insert({
        'id': const Uuid().v4(),
        'recipe_id': _recipeId,
        'inventory_item_id': _selectedInventoryItemId,
        'quantity': qty,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Clear input
      _qtyCtrl.clear();
      _selectedInventoryItemId = null;

      // Reload
      await _loadRecipeAndIngredients();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add ingredient: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteIngredient(String ingredientId) async {
    setState(() => _loading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      await supabase.from(SupabaseConstants.recipeIngredients).delete().eq('id', ingredientId);
      await _loadRecipeAndIngredients();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete ingredient: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInstructions() async {
    if (_recipeId == null) return;
    setState(() => _loading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      await supabase.from(SupabaseConstants.recipes).update({
        'instructions': _instructionsCtrl.text.trim(),
      }).eq('id', _recipeId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instructions saved successfully!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save instructions: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recipe — ${widget.item.name}',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: _loading && _ingredients.isEmpty && _allInventoryItems.isEmpty
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          : SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_recipeId == null) ...[
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            const Icon(Icons.menu_book_outlined, size: 64, color: AppColors.textHint),
                            const SizedBox(height: 12),
                            Text(
                              'No recipe set for this item',
                              style: GoogleFonts.outfit(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _createRecipe,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create Recipe'),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      )
                    ] else ...[
                      // Add Ingredient form
                      Text(
                        'Add Ingredients',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedInventoryItemId,
                              hint: const Text('Select ingredient'),
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                              items: _allInventoryItems.map((item) {
                                return DropdownMenuItem<String>(
                                  value: item['id'] as String,
                                  child: Text('${item['name']} (${item['unit']})'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedInventoryItemId = val;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _qtyCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                hintText: 'Qty',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addIngredient,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            child: const Icon(Icons.add, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Ingredient list
                      Text(
                        'Ingredients List',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      if (_ingredients.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No ingredients added yet.',
                            style: GoogleFonts.outfit(fontStyle: FontStyle.italic, color: AppColors.textHint, fontSize: 12),
                          ),
                        ),
                      ] else ...[
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _ingredients.length,
                          itemBuilder: (ctx, idx) {
                            final ing = _ingredients[idx];
                            final invItem = ing['inventory_items'] as Map<String, dynamic>?;
                            final name = invItem?['name'] as String? ?? 'Unknown';
                            final unit = invItem?['unit'] as String? ?? '';
                            final qty = (ing['quantity'] as num?)?.toDouble() ?? 0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary),
                                    ),
                                  ),
                                  Text(
                                    '$qty $unit',
                                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                    onPressed: () => _deleteIngredient(ing['id'] as String),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Cooking instructions
                      Text(
                        'Cooking / Prep Instructions',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _instructionsCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Enter cooking steps here...',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _saveInstructions,
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save Instructions'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
