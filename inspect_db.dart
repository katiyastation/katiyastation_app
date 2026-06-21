import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('Starting inspection...');
  try {
    final supabase = await Supabase.initialize(
      url: 'https://zmxoakexaobpvmlzwxcu.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpteG9ha2V4YW9icHZtbHp3eGN1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIwMjE2NzIsImV4cCI6MjA5NzU5NzY3Mn0.sRzq1AvmhWc3TE-PJttzDKlbIdLSlPSQVJokg47NbKk',
    );

    final client = supabase.client;

    print('Fetching user profiles...');
    final profiles = await client.from('user_profiles').select();
    print('Total user profiles: ${profiles.length}');
    for (final p in profiles) {
      print('Profile: id=${p['id']}, email=${p['email'] ?? 'N/A'}, full_name=${p['full_name']}, role=${p['role']}');
    }

    print('Executing RPC to test list of all users...');
    try {
      final List<dynamic> allUsers = await client.rpc('get_all_users');
      print('RPC get_all_users returned ${allUsers.length} users:');
      for (final u in allUsers) {
        print('  - Email: ${u['email']}, Role: ${u['role']}, Full Name: ${u['full_name']}, Active: ${u['is_active']}');
      }
    } catch (e) {
      print('Error calling get_all_users RPC: $e');
    }

  } catch (e) {
    print('Failed with error: $e');
  }
}
