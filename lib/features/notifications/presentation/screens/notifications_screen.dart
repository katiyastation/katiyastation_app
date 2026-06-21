import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final notificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return const Stream.empty();
  return supabase.from('notifications').stream(primaryKey: ['id'])
      .eq('branch_id', profile.branchId ?? '').order('created_at', ascending: false)
      .map((rows) => rows);
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text('No notifications', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (ctx, i) {
                  final n = rows[i];
                  final isRead = n['is_read'] as bool? ?? false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isRead ? AppColors.card : AppColors.card.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isRead ? AppColors.border : AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: (isRead ? AppColors.textSecondary : AppColors.primary).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          n['type'] == 'alert' ? Icons.warning_rounded : Icons.info_rounded,
                          color: isRead ? AppColors.textSecondary : AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n['title'] ?? 'Notification', style: GoogleFonts.outfit(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(n['message'] ?? '', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                      ])),
                      const SizedBox(width: 8),
                      Text(
                        n['created_at'] != null ? DateFormat('hh:mm a').format(DateTime.parse(n['created_at'] as String)) : '',
                        style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textHint),
                      ),
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                },
              ),
      ),
    );
  }
}
