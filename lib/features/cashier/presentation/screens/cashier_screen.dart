import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../payment_history/presentation/screens/payment_history_screen.dart';
import '../../../branches/presentation/providers/branch_provider.dart';
import '../../../../core/widgets/thermal_receipt.dart';

// Session billing data provider (KOTs + aggregated items for this session)
// Public (no leading underscore) so realtime_sync.dart can invalidate it
// when a KOT is added/updated on this session from another device.
final sessionBillingProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, sessionId) async {
  if (sessionId.isEmpty) return {'items': [], 'subtotal': 0.0, 'kots': []};

  final response =
      await ApiClient.instance.get(ApiConstants.kotsBySession(sessionId));
  final kots = (response.data as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((k) => k['status'] != 'cancelled')
      .toList();

  final List<Map<String, dynamic>> allItems = [];
  for (final kot in kots) {
    final items = (kot['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((i) => i['status'] != 'cancelled');
    allItems.addAll(items);
  }

  final Map<String, Map<String, dynamic>> aggregated = {};
  for (final item in allItems) {
    final key = item['menu_item_id'] as String;
    if (aggregated.containsKey(key)) {
      aggregated[key]!['quantity'] =
          (aggregated[key]!['quantity'] as int) + (item['quantity'] as int);
    } else {
      aggregated[key] = {
        'menu_item_id': item['menu_item_id'],
        'menu_item_name': item['menu_item_name'] ?? item['name'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      };
    }
  }

  double subtotal = 0;
  for (final item in aggregated.values) {
    subtotal += ((item['unit_price'] as num?)?.toDouble() ?? 0) *
        (item['quantity'] as int);
  }

  return {
    'items': aggregated.values.toList(),
    'subtotal': subtotal,
    'kots': kots,
  };
});

class CashierScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String tableId;

  const CashierScreen({super.key, required this.sessionId, required this.tableId});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen>
    with SingleTickerProviderStateMixin {
  String _paymentMethod = AppConstants.paymentCash;
  double _discount = 0;
  bool _applyServiceCharge = false;
  final bool _applyVat = false;
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  bool _processing = false;
  String? _customerName;
  String? _customerPhone;

  String? _selectedSessionId;
  String? _selectedTableId;

  late AnimationController _pulseController;

  final fmt = NumberFormat('#,##0.00');

  // Payment method configs
  static const _paymentMethods = [
    {'label': 'Cash', 'value': 'cash', 'icon': Icons.payments_rounded},
    {'label': 'Card', 'value': 'card', 'icon': Icons.credit_card_rounded},
    {'label': 'eSewa', 'value': 'esewa', 'icon': Icons.phone_android_rounded},
    {'label': 'Khalti', 'value': 'khalti', 'icon': Icons.account_balance_wallet_rounded},
    {'label': 'FonePay', 'value': 'fonepay', 'icon': Icons.qr_code_scanner_rounded},
    {'label': 'Credit', 'value': 'credit', 'icon': Icons.receipt_long_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedSessionId = widget.sessionId.isEmpty ? null : widget.sessionId;
    _selectedTableId = widget.tableId.isEmpty ? null : widget.tableId;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CashierScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId ||
        widget.tableId != oldWidget.tableId) {
      if (widget.sessionId.isNotEmpty) {
        _selectedSessionId = widget.sessionId;
        _selectedTableId = widget.tableId;
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final tablesAsync = ref.watch(tablesStreamProvider);
    // Pre-warm branch info (name/address/phone) so it's already loaded by
    // the time a receipt or KOT ticket needs to print it.
    ref.watch(currentBranchProvider);
    final isMobile = context.isMobile;

    final workspace = Expanded(
      child: _selectedSessionId == null || _selectedSessionId!.isEmpty
          ? _noSessionView(context, isMobile: isMobile)
          : ref.watch(sessionBillingProvider(_selectedSessionId!)).when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (data) => _buildBillingView(data, profile, isMobile: isMobile),
              ),
    );

    if (isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: _buildAppBar(showDrawerIcon: true),
        drawer: Drawer(
          width: 280,
          child: SafeArea(child: _buildTablesSidebar(tablesAsync)),
        ),
        body: workspace,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: _buildAppBar(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left sidebar ──────────────────────────────────────────────
          _buildTablesSidebar(tablesAsync),
          // ── Right workspace ───────────────────────────────────────────
          workspace,
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  APP BAR
  // ─────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar({bool showDrawerIcon = false}) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: showDrawerIcon
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Select Table',
              ),
            )
          : IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary, size: 18),
              ),
              onPressed: () => context.go('/tables'),
            ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.point_of_sale_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cashier Station',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                DateFormat('EEEE, dd MMM yyyy · HH:mm').format(DateTime.now()),
                style: GoogleFonts.outfit(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  LEFT SIDEBAR
  // ─────────────────────────────────────────────────────────
  Widget _buildTablesSidebar(AsyncValue tablesAsync) {
    return Container(
      width: 260,
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.table_restaurant_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Active Tables',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                tablesAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (tables) {
                    final count =
                        (tables as List).where((t) => t.isOccupied || t.isReadyForBilling).length;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: tablesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (tables) {
                final occupied =
                    (tables as List).where((t) => t.isOccupied || t.isReadyForBilling).toList();
                if (occupied.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_circle_outline_rounded,
                                size: 32, color: AppColors.success),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'All tables free',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No occupied tables right now',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: AppColors.textHint),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: occupied.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (ctx, i) {
                    final t = occupied[i];
                    final isSelected = t.id == _selectedTableId;
                    final isReq = t.billRequested;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedTableId = t.id;
                          _selectedSessionId = t.currentSessionId;
                        });
                        if (context.isMobile) Navigator.of(ctx).pop();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Table icon
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : (isReq
                                        ? AppColors.warning
                                            .withValues(alpha: 0.12)
                                        : const Color(0xFFF0F2F5)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${t.tableNumber}',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? AppColors.primary
                                      : (isReq
                                          ? AppColors.warning
                                          : AppColors.textSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Table ${t.tableNumber}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    t.section,
                                    style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        color: AppColors.textHint),
                                  ),
                                ],
                              ),
                            ),
                            if (isReq)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'BILL',
                                  style: GoogleFonts.outfit(
                                    fontSize: 8,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ).animate(onPlay: (c) => c.repeat(reverse: true))
                                  .fade(duration: 600.ms)
                            else
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.tableOccupied,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  NO SESSION VIEW
  // ─────────────────────────────────────────────────────────
  Widget _noSessionView(BuildContext context, {bool isMobile = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              size: 56,
              color: AppColors.primary,
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 20),
          Text(
            'Cashier Station',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),
          const SizedBox(height: 8),
          Text(
            isMobile
                ? 'Tap the ☰ menu icon to select an active table.'
                : 'Choose an occupied table from the sidebar\nto load the billing workspace.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                fontSize: 14, color: AppColors.textSecondary, height: 1.6),
          ).animate().fadeIn(delay: 200.ms),
          if (isMobile) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.table_restaurant_rounded, size: 18),
              label: const Text('Select Table'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ).animate().fadeIn(delay: 300.ms),
          ],
        ],
      ),
    );
  }


  // ─────────────────────────────────────────────────────────
  //  BILLING VIEW
  // ─────────────────────────────────────────────────────────
  Widget _buildBillingView(Map<String, dynamic> data, dynamic profile,
      {bool isMobile = false}) {
    final items = data['items'] as List<Map<String, dynamic>>;
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final afterService = subtotal + serviceCharge - _discount;
    final vat = _applyVat ? afterService * 0.13 : 0.0;
    final total = afterService + vat;
    final amountPaid = double.tryParse(_amountCtrl.text) ?? 0;
    final change = amountPaid - total;

    // Mobile: single column scroll
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerSection(),
            const SizedBox(height: 16),
            _buildOrderItemsSection(items),
            const SizedBox(height: 16),
            _buildAdjustmentsSection(subtotal),
            const SizedBox(height: 16),
            _buildPaymentPanel(
                subtotal, serviceCharge, vat, total, amountPaid, change,
                items, data, profile,
                mobileMode: true),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Centre columns (Customer · Items · Adjustments) ─────────
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Customer section ────────────────────────────────
                _buildCustomerSection(),
                const SizedBox(height: 16),
                // ── Order items section ─────────────────────────────
                _buildOrderItemsSection(items),
                const SizedBox(height: 16),
                // ── Adjustments section ─────────────────────────────
                _buildAdjustmentsSection(subtotal),
              ],
            ),
          ),
        ),
        // ── Right payment panel ─────────────────────────────────────
        _buildPaymentPanel(
            subtotal, serviceCharge, vat, total, amountPaid, change, items, data, profile),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CUSTOMER SECTION
  // ─────────────────────────────────────────────────────────
  Widget _buildCustomerSection() {
    final hasCustomer = _customerName != null;
    return _PremiumSectionCard(
      icon: Icons.person_rounded,
      iconColor: const Color(0xFF2980B9),
      iconBg: const Color(0xFFEBF5FB),
      title: 'Customer',
      trailing: TextButton.icon(
        icon: Icon(
          hasCustomer ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
          size: 14,
        ),
        label: Text(hasCustomer ? 'Change' : 'Assign'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.primary),
          ),
        ),
        onPressed: _showCustomerPicker,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: hasCustomer
                  ? const LinearGradient(
                      colors: [Color(0xFF2980B9), Color(0xFF1F618D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: hasCustomer ? null : const Color(0xFFF0F2F5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: hasCustomer
                  ? Text(
                      (_customerName ?? 'W')[0].toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_outline_rounded,
                      size: 22, color: AppColors.textHint),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customerName ?? 'Walk-in Customer',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (_customerPhone != null) ...[
                      const Icon(Icons.phone_rounded,
                          size: 12, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        _customerPhone!,
                        style: GoogleFonts.outfit(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ] else
                      Text(
                        'No contact information',
                        style: GoogleFonts.outfit(
                            fontSize: 12, color: AppColors.textHint),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ORDER ITEMS SECTION
  // ─────────────────────────────────────────────────────────
  Widget _buildOrderItemsSection(List<Map<String, dynamic>> items) {
    return _PremiumSectionCard(
      icon: Icons.receipt_rounded,
      iconColor: const Color(0xFF8E44AD),
      iconBg: const Color(0xFFF5EEF8),
      title: 'Order Items',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF8E44AD).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${items.length} item${items.length == 1 ? '' : 's'}',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF8E44AD),
          ),
        ),
      ),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No items in this order yet',
                  style: GoogleFonts.outfit(
                      fontSize: 13, color: AppColors.textHint),
                ),
              ),
            )
          : Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ITEM',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHint,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Text(
                        'QTY',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 90,
                        child: Text(
                          'AMOUNT',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHint,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final itemTotal =
                      ((item['unit_price'] as num?)?.toDouble() ?? 0) *
                          (item['quantity'] as int);
                  final unitPrice =
                      (item['unit_price'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        // Index bubble
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8E44AD).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8E44AD),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['menu_item_name'] ?? item['name'] ?? 'Unknown Item') as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'NPR ${fmt.format(unitPrice)} each',
                                style: GoogleFonts.outfit(
                                    fontSize: 11, color: AppColors.textHint),
                              ),
                            ],
                          ),
                        ),
                        // Qty badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '×${item['quantity']}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 90,
                          child: Text(
                            'NPR ${fmt.format(itemTotal)}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ADJUSTMENTS SECTION
  // ─────────────────────────────────────────────────────────
  Widget _buildAdjustmentsSection(double subtotal) {
    return _PremiumSectionCard(
      icon: Icons.tune_rounded,
      iconColor: const Color(0xFFF39C12),
      iconBg: const Color(0xFFFEF9E7),
      title: 'Adjustments & Charges',
      child: Column(
        children: [
          // Service charge toggle
          _buildToggleRow(
            icon: Icons.room_service_rounded,
            label: 'Service Charge',
            sublabel: '10% of subtotal',
            value: _applyServiceCharge,
            valueLabel: _applyServiceCharge
                ? '+ NPR ${fmt.format(subtotal * 0.1)}'
                : 'Off',
            valueColor: _applyServiceCharge
                ? AppColors.warning
                : AppColors.textHint,
            onChanged: (v) => setState(() => _applyServiceCharge = v),
          ),
          // VAT toggle removed
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          // Discount field
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_offer_rounded,
                    size: 16, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discount',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Flat discount in NPR',
                      style: GoogleFonts.outfit(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    prefixText: 'NPR ',
                    prefixStyle: GoogleFonts.outfit(
                        fontSize: 12, color: AppColors.textHint),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.success, width: 1.5),
                    ),
                    filled: true,
                    fillColor: AppColors.success.withValues(alpha: 0.04),
                  ),
                  onChanged: (v) =>
                      setState(() => _discount = double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool value,
    required String valueLabel,
    required Color valueColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: valueColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                sublabel,
                style: GoogleFonts.outfit(
                    fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            valueLabel,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: valueColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PAYMENT PANEL (right side)
  // ─────────────────────────────────────────────────────────
  Widget _buildPaymentPanel(
    double subtotal,
    double serviceCharge,
    double vat,
    double total,
    double amountPaid,
    double change,
    List items,
    Map<String, dynamic> data,
    dynamic profile, {
    bool mobileMode = false,
  }) {
    final containerDecoration = mobileMode
        ? BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          )
        : const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.border)),
          );
    return Container(
      width: mobileMode ? double.infinity : 340,
      decoration: containerDecoration,
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Bill Summary',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          // ── Scrollable content ──────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bill breakdown card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _PremiumBillRow(
                          label: 'Subtotal',
                          value: 'NPR ${fmt.format(subtotal)}',
                        ),
                        if (_applyServiceCharge) ...[
                          const SizedBox(height: 8),
                          _PremiumBillRow(
                            label: 'Service Charge (10%)',
                            value: '+ NPR ${fmt.format(serviceCharge)}',
                            valueColor: AppColors.warning,
                          ),
                        ],
                        if (_discount > 0) ...[
                          const SizedBox(height: 8),
                          _PremiumBillRow(
                            label: 'Discount',
                            value: '- NPR ${fmt.format(_discount)}',
                            valueColor: AppColors.success,
                          ),
                        ],
                        if (_applyVat) ...[
                          const SizedBox(height: 8),
                          _PremiumBillRow(
                            label: 'VAT (13%)',
                            value: '+ NPR ${fmt.format(vat)}',
                            valueColor: const Color(0xFF2980B9),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(height: 1, color: AppColors.border),
                        const SizedBox(height: 12),
                        // Total row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'NPR ${fmt.format(total)}',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Payment method label
                  Text(
                    'PAYMENT METHOD',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textHint,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Payment method grid
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.4,
                    children: _paymentMethods.map((pm) {
                      final isSelected = _paymentMethod == pm['value'];
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _paymentMethod = pm['value'] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                pm['icon'] as IconData,
                                size: 13,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                pm['label'] as String,
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Cash amount input
                  if (_paymentMethod == 'cash') ...[
                    const SizedBox(height: 16),
                    Text(
                      'AMOUNT RECEIVED',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textHint,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        prefixText: 'NPR  ',
                        prefixStyle: GoogleFonts.outfit(
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                        hintText: '0.00',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 18,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w700,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    // Change display
                    if (amountPaid > 0) ...[
                      const SizedBox(height: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: change >= 0
                              ? AppColors.success.withValues(alpha: 0.08)
                              : AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: change >= 0
                                ? AppColors.success.withValues(alpha: 0.3)
                                : AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  change >= 0
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  size: 14,
                                  color: change >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  change >= 0 ? 'Change Due' : 'Amount Short',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: change >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'NPR ${fmt.format(change.abs())}',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: change >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  if (_paymentMethod == 'credit') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This will create a credit (Udhaaro) record for NPR ${fmt.format(total)}.',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.warning,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Action buttons ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                // Settle bill button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _processing
                        ? null
                        : () => _settleBill(
                            total, subtotal, serviceCharge, vat, profile, items, data),
                    child: _processing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _paymentMethod == 'credit'
                                    ? Icons.receipt_long_rounded
                                    : Icons.check_circle_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _paymentMethod == 'credit'
                                    ? 'Record Credit (Udhaaro)'
                                    : 'Settle Bill',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                // Print bill button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _printBill(total, items, data),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.print_rounded, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Print Bill',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  SETTLE BILL
  // ─────────────────────────────────────────────────────────
  Future<void> _settleBill(double total, double subtotal,
      double serviceCharge, double vat, dynamic profile,
      List items, Map<String, dynamic> data) async {
    if (_selectedSessionId == null || _selectedTableId == null) return;
    setState(() => _processing = true);
    try {
      final amountPaid = _paymentMethod == 'cash'
          ? (double.tryParse(_amountCtrl.text) ?? total)
          : total;

      final response = await ApiClient.instance.post(
        ApiConstants.generateBill(_selectedSessionId!),
        data: {
          'discount': _discount,
          'paymentMethod': _paymentMethod,
          'amountPaid': amountPaid,
          if (_customerName != null) 'customerName': _customerName,
          if (_customerPhone != null) 'customerPhone': _customerPhone,
          'applyServiceCharge': _applyServiceCharge,
          'applyVat': _applyVat,
        },
      );
      final bill = response.data as Map<String, dynamic>;
      final invoiceNum = bill['invoice_number'] as String? ?? '';

      ref.invalidate(tablesStreamProvider);
      ref.invalidate(tableSessionProvider(_selectedTableId!));
      ref.invalidate(dashboardBillsProvider);
      ref.invalidate(dashboardCreditProvider);
      ref.invalidate(dashboardSessionsProvider);
      ref.invalidate(billsStreamProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Bill settled! Invoice: $invoiceNum',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );

        // Show the real, final receipt (actual invoice/bill number,
        // payment method, amount paid, change) right after settling —
        // this is the one that matters, the pre-settle "Print Bill"
        // button is only ever a preview since no invoice exists yet.
        _printReceipt(bill, items);

        setState(() {
          _selectedSessionId = null;
          _selectedTableId = null;
          _customerName = null;
          _customerPhone = null;
          _discount = 0;
          _discountCtrl.text = '0';
          _amountCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            content: Text('Error: $e',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  // ─────────────────────────────────────────────────────────
  //  PRINT BILL (pre-settle preview — no invoice number yet)
  // ─────────────────────────────────────────────────────────
  void _printBill(double total, List items, Map<String, dynamic> data) {
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final tables = ref.read(tablesStreamProvider).value ?? [];
    final selectedTable = tables.where((t) => t.id == _selectedTableId).firstOrNull;
    final tableNumber = selectedTable?.tableNumber ?? 'N/A';

    final sessions = ref.read(activeSessionsStreamProvider).value ?? [];
    final selectedSession = sessions.where((s) => s.id == _selectedSessionId).firstOrNull;
    final sessionNumber = selectedSession?.sessionNumber ??
        (_selectedSessionId != null ? _selectedSessionId!.substring(0, 8) : 'N/A');

    final branch = ref.read(currentBranchProvider).value;

    showThermalPrintDialog(
      context,
      title: 'Thermal Print Preview',
      onPrint: () => showPrintSentSnackbar(context),
      receipt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptBranchHeader(branch),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Date:', dateStr),
          receiptRow('Table:', tableNumber),
          receiptRow('Session:', sessionNumber),
          if (_customerName != null) receiptRow('Customer:', _customerName!),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          ...items.map((item) {
            final name = item['menu_item_name'] as String;
            final qty = item['quantity'] as int;
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            return receiptRow('$name x$qty', fmt.format(price * qty), fontSize: 12);
          }),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Subtotal:', fmt.format(subtotal)),
          if (_applyServiceCharge) receiptRow('Service (10%):', fmt.format(serviceCharge)),
          if (_discount > 0) receiptRow('Discount:', '-${fmt.format(_discount)}'),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('TOTAL:', 'NPR ${fmt.format(total)}', fontSize: 14, weight: FontWeight.bold),
          const SizedBox(height: 8),
          Text('*** PREVIEW — not a valid receipt ***',
              textAlign: TextAlign.center, style: receiptStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PRINT RECEIPT — the real, final receipt after a bill is settled,
  //  built from the backend's actual invoice/bill numbers and totals.
  // ─────────────────────────────────────────────────────────
  void _printReceipt(Map<String, dynamic> bill, List items) {
    final branch = ref.read(currentBranchProvider).value;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.tryParse(bill['created_at'] as String? ?? '') ?? DateTime.now());

    final subtotal = (bill['sub_total'] as num?)?.toDouble() ?? 0;
    final discount = (bill['discount'] as num?)?.toDouble() ?? 0;
    final serviceCharge = (bill['service_charge'] as num?)?.toDouble() ?? 0;
    final vatAmount = (bill['vat_amount'] as num?)?.toDouble() ?? 0;
    final totalAmount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
    final amountPaid = (bill['amount_paid'] as num?)?.toDouble() ?? 0;
    final changeAmount = (bill['change_amount'] as num?)?.toDouble() ?? 0;
    final paymentMethod = (bill['payment_method'] as String? ?? '').toUpperCase();
    final customerName = bill['customer_name'] as String?;
    final cashierName = bill['cashier_name'] as String?;

    showThermalPrintDialog(
      context,
      title: 'Receipt',
      onPrint: () => showPrintSentSnackbar(context, label: 'Receipt sent to thermal printer!'),
      receipt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptBranchHeader(branch),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Invoice No:', bill['invoice_number'] as String? ?? '—', weight: FontWeight.bold),
          receiptRow('Bill No:', bill['bill_number'] as String? ?? '—'),
          receiptRow('Date:', dateStr),
          if (cashierName != null) receiptRow('Cashier:', cashierName),
          if (customerName != null) receiptRow('Customer:', customerName),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          ...items.map((item) {
            final name = item['menu_item_name'] as String;
            final qty = item['quantity'] as int;
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            return receiptRow('$name x$qty', fmt.format(price * qty), fontSize: 12);
          }),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Subtotal:', fmt.format(subtotal)),
          if (serviceCharge > 0) receiptRow('Service Charge:', fmt.format(serviceCharge)),
          if (discount > 0) receiptRow('Discount:', '-${fmt.format(discount)}'),
          if (vatAmount > 0) receiptRow('VAT:', fmt.format(vatAmount)),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('TOTAL:', 'NPR ${fmt.format(totalAmount)}', fontSize: 14, weight: FontWeight.bold),
          const SizedBox(height: 4),
          receiptRow('Payment Method:', paymentMethod),
          receiptRow('Amount Paid:', fmt.format(amountPaid)),
          if (changeAmount > 0) receiptRow('Change:', fmt.format(changeAmount)),
          const SizedBox(height: 8),
          Text('Thank you for dining with us!',
              textAlign: TextAlign.center, style: receiptStyle()),
          Text('Powered by Katiya Station RMS',
              textAlign: TextAlign.center, style: receiptStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CUSTOMER PICKER DIALOG
  // ─────────────────────────────────────────────────────────
  void _showCustomerPicker() async {
    final nameCtrl =
        TextEditingController(text: _customerName ?? '');
    final phoneCtrl =
        TextEditingController(text: _customerPhone ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF5FB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_rounded,
                  color: Color(0xFF2980B9), size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Customer Information',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Customer Name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Icons.phone_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              setState(() {
                _customerName = nameCtrl.text.trim().isEmpty
                    ? null
                    : nameCtrl.text.trim();
                _customerPhone = phoneCtrl.text.trim().isEmpty
                    ? null
                    : phoneCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumSectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final Widget? trailing;
  final Widget child;

  const _PremiumSectionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _PremiumBillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PremiumBillRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
