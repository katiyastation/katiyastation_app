import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _printKotAutomatically = true;
  bool _printReceiptAutomatically = true;
  String _printerIp = '192.168.1.100';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Restaurant profile
            const _SectionHeader('Branch Details'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.store_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppConstants.restaurantName, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text('Branch ID: ${profile?.branchId ?? "Default Branch"}', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                ])),
              ]),
            ),
            const SizedBox(height: 24),
            // Printer Configuration
            const _SectionHeader('Thermal Printer Settings (ESC/POS)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                SwitchListTile(
                  title: Text('Auto-print KOT on send', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                  value: _printKotAutomatically,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _printKotAutomatically = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                SwitchListTile(
                  title: Text('Auto-print receipt on settle', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                  value: _printReceiptAutomatically,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _printReceiptAutomatically = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                ListTile(
                  title: Text('Printer IP Address', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                  subtitle: Text(_printerIp, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  contentPadding: EdgeInsets.zero,
                  onTap: _showPrinterIpDialog,
                ),
              ]),
            ),
            const SizedBox(height: 24),
            // Security / System info
            const _SectionHeader('System Info'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: const Column(children: [
                _InfoRow('App Version', '1.0.0'),
                Divider(),
                _InfoRow('Database Host', 'Supabase Cloud'),
                Divider(),
                _InfoRow('Local Cache Status', 'Ready'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrinterIpDialog() {
    final ctrl = TextEditingController(text: _printerIp);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Printer IP Configuration'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'IP Address (e.g. 192.168.1.100)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () {
          setState(() => _printerIp = ctrl.text.trim());
          Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.5));
}

class _InfoRow extends StatelessWidget {
  final String l, v;
  const _InfoRow(this.l, this.v);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(l, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
      Text(v, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ],
  );
}
