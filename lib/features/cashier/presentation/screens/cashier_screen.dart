import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../tables/presentation/providers/tables_provider.dart';

// Real-time session billing data provider
final _sessionBillingProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, sessionId) {
  if (sessionId.isEmpty) return const Stream.empty();
  final supabase = ref.watch(supabaseProvider);
  // Stream KOTs for this session; on each update, load items
  return supabase
      .from(SupabaseConstants.kots)
      .stream(primaryKey: ['id'])
      .eq('session_id', sessionId)
      .order('created_at')
      .asyncMap((kotRows) async {
        final kots =
            kotRows.where((k) => k['status'] != 'cancelled').toList();

        List<Map<String, dynamic>> allItems = [];
        for (final kot in kots) {
          final items = await supabase
              .from(SupabaseConstants.kotItems)
              .select()
              .eq('kot_id', kot['id'] as String);
          allItems.addAll(List<Map<String, dynamic>>.from(items));
        }

        // Aggregate items by menu_item_id
        final Map<String, Map<String, dynamic>> aggregated = {};
        for (final item in allItems) {
          final key = item['menu_item_id'] as String;
          if (aggregated.containsKey(key)) {
            aggregated[key]!['quantity'] =
                (aggregated[key]!['quantity'] as int) +
                    (item['quantity'] as int);
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
          subtotal +=
              ((item['unit_price'] as num?)?.toDouble() ?? 0) *
              (item['quantity'] as int);
        }

        return {
          'items': aggregated.values.toList(),
          'subtotal': subtotal,
          'kots': kots,
        };
      });
});

class CashierScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String tableId;

  const CashierScreen({super.key, required this.sessionId, required this.tableId});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  String _paymentMethod = AppConstants.paymentCash;
  double _discount = 0;
  bool _applyServiceCharge = false;
  bool _applyVat = true;
  final _amountCtrl = TextEditingController();
  bool _processing = false;
  String? _customerName;
  String? _customerPhone;

  String? _selectedSessionId;
  String? _selectedTableId;

  final fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _selectedSessionId = widget.sessionId.isEmpty ? null : widget.sessionId;
    _selectedTableId = widget.tableId.isEmpty ? null : widget.tableId;
  }

  @override
  void didUpdateWidget(covariant CashierScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId || widget.tableId != oldWidget.tableId) {
      if (widget.sessionId.isNotEmpty) {
        _selectedSessionId = widget.sessionId;
        _selectedTableId = widget.tableId;
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final tablesAsync = ref.watch(tablesStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/tables'),
        ),
        title: const Text('Cashier / Billing Station'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Active Occupied Tables Sidebar
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.table_restaurant_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Active Tables',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: tablesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (tables) {
                      final occupied = tables.where((t) => t.isOccupied).toList();
                      if (occupied.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, size: 40, color: AppColors.success),
                                const SizedBox(height: 12),
                                Text(
                                  'No occupied tables',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: occupied.length,
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
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : (isReq ? AppColors.warning.withValues(alpha: 0.05) : Colors.transparent),
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isReq ? AppColors.warning : Colors.transparent),
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Table ${t.tableNumber}',
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          t.section,
                                          style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isReq)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'BILL REQ',
                                        style: GoogleFonts.outfit(
                                          fontSize: 9,
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(duration: 600.ms)
                                  else
                                    Container(
                                      width: 6,
                                      height: 6,
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
          ),
          // Right: Billing Workspace
          Expanded(
            child: _selectedSessionId == null || _selectedSessionId!.isEmpty
                ? _noSessionView(context)
                : ref.watch(_sessionBillingProvider(_selectedSessionId!)).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    error: (e, _) =>
                        Center(child: Text('Error loading session: $e')),
                    data: (data) => _buildBillingView(data, profile),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _noSessionView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.point_of_sale_outlined, size: 80, color: AppColors.textHint),
          const SizedBox(height: 20),
          Text('No Table Selected', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Select an occupied table from the left sidebar to start billing',
              style: GoogleFonts.outfit(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBillingView(Map<String, dynamic> data, dynamic profile) {
    final items = data['items'] as List<Map<String, dynamic>>;
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final afterService = subtotal + serviceCharge - _discount;
    final vat = _applyVat ? afterService * 0.13 : 0.0;
    final total = afterService + vat;
    final amountPaid = double.tryParse(_amountCtrl.text) ?? 0;
    final change = amountPaid - total;

    return Row(
      children: [
        // Left: Bill details
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Customer info
                _SectionCard(
                  title: 'Customer',
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_customerName ?? 'Walk-in Customer',
                                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            if (_customerPhone != null)
                              Text(_customerPhone!, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.person_search_rounded, size: 16),
                        label: const Text('Assign'),
                        onPressed: _showCustomerPicker,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Items
                _SectionCard(
                  title: 'Order Items',
                  child: Column(
                    children: [
                      ...items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('×${item['quantity']}',
                                      style: GoogleFonts.outfit(
                                          fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(item['menu_item_name'] as String,
                                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                                ),
                                Text(
                                  'NPR ${fmt.format(((item['unit_price'] as num?)?.toDouble() ?? 0) * (item['quantity'] as int))}',
                                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Adjustments
                _SectionCard(
                  title: 'Adjustments',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Service Charge (10%)', style: TextStyle(color: AppColors.textSecondary)),
                          const Spacer(),
                          Switch(
                            value: _applyServiceCharge,
                            onChanged: (v) => setState(() => _applyServiceCharge = v),
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('VAT (13%)', style: TextStyle(color: AppColors.textSecondary)),
                          const Spacer(),
                          Switch(
                            value: _applyVat,
                            onChanged: (v) => setState(() => _applyVat = v),
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Discount (NPR)', style: TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue: _discount.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
                              onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right: Payment
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              // Bill summary
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bill Summary',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 16),
                      _BillRow('Subtotal', 'NPR ${fmt.format(subtotal)}'),
                      if (_applyServiceCharge)
                        _BillRow('Service Charge (10%)', 'NPR ${fmt.format(serviceCharge)}'),
                      if (_discount > 0)
                        _BillRow('Discount', '-NPR ${fmt.format(_discount)}', isRed: true),
                      if (_applyVat)
                        _BillRow('VAT (13%)', 'NPR ${fmt.format(vat)}'),
                      const Divider(height: 24),
                      _BillRow('TOTAL', 'NPR ${fmt.format(total)}', isBold: true),
                      const SizedBox(height: 24),
                      // Payment method
                      Text('Payment Method',
                          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPaymentChip('Cash', 'cash', Icons.money_rounded),
                          _buildPaymentChip('Card', 'card', Icons.credit_card_rounded),
                          _buildPaymentChip('eSewa', 'esewa', Icons.phone_android_rounded),
                          _buildPaymentChip('Khalti', 'khalti', Icons.account_balance_wallet_rounded),
                          _buildPaymentChip('FonePay', 'fonepay', Icons.qr_code_scanner_rounded),
                          _buildPaymentChip('Credit', 'credit', Icons.receipt_long_rounded),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_paymentMethod == 'cash') ...[
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Amount Received'),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (change >= 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Change', style: GoogleFonts.outfit(color: AppColors.success)),
                                Text('NPR ${fmt.format(change)}',
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.success)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: _processing
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(_paymentMethod == 'credit' ? 'Record Credit (Udhaaro)' : 'Settle Bill'),
                        onPressed: _processing ? null : () => _settleBill(total, subtotal, serviceCharge, vat, profile),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print Bill'),
                        onPressed: () => _printBill(total, items, data),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentChip(String label, String value, IconData icon) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _settleBill(double total, double subtotal, double serviceCharge, double vat, dynamic profile) async {
    if (_selectedSessionId == null || _selectedTableId == null) return;
    setState(() => _processing = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final billId = const Uuid().v4();

      // Get invoice number
      final billCount = await supabase.from(SupabaseConstants.bills).select('id');
      final invoiceNum = 'INV-${(billCount.length + 1).toString().padLeft(4, '0')}';

      final billData = {
        'id': billId,
        'branch_id': profile?.branchId,
        'session_id': _selectedSessionId,
        'table_id': _selectedTableId,
        'invoice_number': invoiceNum,
        'cashier_id': profile?.id,
        'cashier_name': profile?.fullName,
        'customer_name': _customerName,
        'customer_phone': _customerPhone,
        'subtotal': subtotal,
        'discount': _discount,
        'service_charge': serviceCharge,
        'vat_amount': vat,
        'total_amount': total,
        'payment_method': _paymentMethod,
        'payment_status': _paymentMethod == 'credit' ? 'credit' : 'paid',
        'amount_paid': _paymentMethod == 'cash' ? (double.tryParse(_amountCtrl.text) ?? total) : total,
        'change_amount': _paymentMethod == 'cash' ? ((double.tryParse(_amountCtrl.text) ?? total) - total) : 0,
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from(SupabaseConstants.bills).insert(billData);

      // If credit, create credit record
      if (_paymentMethod == 'credit') {
        await supabase.from(SupabaseConstants.creditRecords).insert({
          'id': const Uuid().v4(),
          'branch_id': profile?.branchId,
          'bill_id': billId,
          'customer_name': _customerName ?? 'Unknown',
          'customer_phone': _customerPhone,
          'credit_amount': total,
          'paid_amount': 0,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Close session
      await supabase.from(SupabaseConstants.tableSessions)
          .update({'status': 'billed', 'closed_at': DateTime.now().toIso8601String()})
          .eq('id', _selectedSessionId!);

      // Free table and clear bill request flag
      await supabase.from(SupabaseConstants.restaurantTables)
          .update({
            'status': 'available', 
            'current_session_id': null,
            'bill_requested': false,
            'bill_requested_at': null,
          })
          .eq('id', _selectedTableId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 10),
              Text('Bill settled! Invoice: $invoiceNum'),
            ]),
          ),
        );
        setState(() {
          _selectedSessionId = null;
          _selectedTableId = null;
          _customerName = null;
          _customerPhone = null;
          _discount = 0;
          _amountCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  void _printBill(double total, List items, Map<String, dynamic> data) {
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final afterService = subtotal + serviceCharge - _discount;
    final vat = _applyVat ? afterService * 0.13 : 0.0;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 380,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Thermal Print Preview',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              // Receipt Container
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('KATIYA STATION',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                    Text('Branch Address, Nepal',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black)),
                    Text('Tel: +977-1-XXXXXXXX | VAT: 123456789',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black)),
                    const Text('- - - - - - - - - - - - - - - - - - - - -',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black)),
                    const SizedBox(height: 4),
                    _receiptRow('Date:', dateStr),
                    _receiptRow('Table ID:', _selectedTableId != null ? _selectedTableId!.substring(0, 8) : 'N/A'),
                    _receiptRow('Session:', _selectedSessionId != null ? _selectedSessionId!.substring(0, 8) : 'N/A'),
                    const SizedBox(height: 4),
                    const Text('- - - - - - - - - - - - - - - - - - - - -',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black)),
                    const SizedBox(height: 4),
                    // Items list
                    ...items.map((item) {
                      final name = item['menu_item_name'] as String;
                      final qty = item['quantity'] as int;
                      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final itemTotal = price * qty;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '$name x$qty',
                                style: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black),
                              ),
                            ),
                            Text(
                              fmt.format(itemTotal),
                              style: GoogleFonts.courierPrime(fontSize: 12, color: Colors.black),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    const Text('- - - - - - - - - - - - - - - - - - - - -',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black)),
                    const SizedBox(height: 4),
                    _receiptRow('Subtotal:', fmt.format(subtotal)),
                    if (_applyServiceCharge)
                      _receiptRow('Service Charge (10%):', fmt.format(serviceCharge)),
                    if (_discount > 0)
                      _receiptRow('Discount:', '-${fmt.format(_discount)}'),
                    if (_applyVat)
                      _receiptRow('VAT (13%):', fmt.format(vat)),
                    const SizedBox(height: 4),
                    const Text('- - - - - - - - - - - - - - - - - - - - -',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL:',
                            style: GoogleFonts.courierPrime(
                                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                        Text('NPR ${fmt.format(total)}',
                            style: GoogleFonts.courierPrime(
                                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Thank you for dining with us!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black)),
                    Text('Powered by Katiya Station RMS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(fontSize: 9, color: Colors.black)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print Now'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.print, color: AppColors.success),
                              SizedBox(width: 10),
                              Text('Print command sent to ESC/POS thermal printer successfully!'),
                            ],
                          ),
                          backgroundColor: AppColors.surfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black)),
          Text(value, style: GoogleFonts.courierPrime(fontSize: 11, color: Colors.black)),
        ],
      ),
    );
  }

  void _showCustomerPicker() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customer Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name')),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _customerName = nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
                _customerPhone = phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim();
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final bool isRed;

  const _BillRow(this.label, this.value, {this.isBold = false, this.isRed = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.outfit(
                fontSize: isBold ? 16 : 13,
                color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              )),
          Text(value,
              style: GoogleFonts.outfit(
                fontSize: isBold ? 18 : 13,
                color: isRed ? AppColors.error : (isBold ? AppColors.primary : AppColors.textSecondary),
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              )),
        ],
      ),
    );
  }
}
