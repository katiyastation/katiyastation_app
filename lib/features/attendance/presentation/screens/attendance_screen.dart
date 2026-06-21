import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _loading = true;
  Map<String, dynamic>? _todayRecord;

  @override
  void initState() { super.initState(); _loadTodayRecord(); }

  Future<void> _loadTodayRecord() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile == null) return;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    try {
      final data = await ref.read(supabaseProvider)
          .from(SupabaseConstants.attendance)
          .select()
          .eq('employee_id', profile.id)
          .gte('check_in', '${todayStr}T00:00:00')
          .lte('check_in', '${todayStr}T23:59:59')
          .maybeSingle();
      if (mounted) setState(() { _todayRecord = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final checkedIn = _todayRecord != null;
    final checkedOut = _todayRecord?['check_out'] != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Attendance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (checkedOut ? AppColors.textSecondary : (checkedIn ? AppColors.success : AppColors.primary)).withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 56,
                          color: checkedOut ? AppColors.textSecondary : (checkedIn ? AppColors.success : AppColors.primary),
                        ),
                      ).animate().scale(duration: 400.ms, curve: Curves.backOut),
                      const SizedBox(height: 32),
                      Text(
                        checkedOut ? 'Shift Completed' : (checkedIn ? 'You are Checked In' : 'Not Checked In Yet'),
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        checkedOut 
                            ? 'See you tomorrow!' 
                            : (checkedIn 
                                ? 'Checked in at: ${DateFormat('hh:mm a').format(DateTime.parse(_todayRecord!['check_in']))}' 
                                : 'Press the button below to mark check-in for today'),
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
                        textAlign: Center,
                      ),
                      const SizedBox(height: 48),
                      if (!checkedIn)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Mark Check-In'),
                            onPressed: () => _markAttendance(true, profile),
                          ),
                        )
                      else if (!checkedOut)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Mark Check-Out'),
                            onPressed: () => _markAttendance(false, profile),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                              const SizedBox(width: 10),
                              Text('Attendance for today is complete.', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _markAttendance(bool isCheckIn, dynamic profile) async {
    if (profile == null) return;
    setState(() => _loading = true);
    final supabase = ref.read(supabaseProvider);

    try {
      if (isCheckIn) {
        final id = const Uuid().v4();
        await supabase.from(SupabaseConstants.attendance).insert({
          'id': id,
          'branch_id': profile.branchId,
          'employee_id': profile.id,
          'employee_name': profile.fullName,
          'check_in': DateTime.now().toIso8601String(),
        });
      } else {
        await supabase.from(SupabaseConstants.attendance).update({
          'check_out': DateTime.now().toIso8601String(),
        }).eq('id', _todayRecord!['id']);
      }
      await _loadTodayRecord();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking attendance: $e'), backgroundColor: AppColors.error),
        );
      }
      setState(() => _loading = false);
    }
  }
}
