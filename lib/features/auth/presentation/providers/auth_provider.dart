import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_profile.dart';
import '../../../../core/constants/supabase_constants.dart';

// Supabase client provider
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// Auth state stream provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

// Current user provider
final currentUserProvider = Provider<User?>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.auth.currentUser;
});

// Current user profile provider
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final supabase = ref.watch(supabaseProvider);
  final data = await supabase
      .from(SupabaseConstants.userProfiles)
      .select()
      .eq('id', user.id)
      .maybeSingle();

  if (data == null) return null;
  return UserProfile.fromJson(data);
});

// Current profile alias
final currentProfileProvider = currentUserProfileProvider;

// User role provider
final userRoleProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProfileProvider).value?.role;
});

// Auth notifier
class AuthNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AsyncValue.loading());

  SupabaseClient get _supabase => _ref.read(supabaseProvider);

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (response.user == null) {
        state = AsyncValue.error('Login failed. Please check your credentials.', StackTrace.current);
        return;
      }
      final profileData = await _supabase
          .from(SupabaseConstants.userProfiles)
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();

      if (profileData == null) {
        state = AsyncValue.error('User profile not found. Contact your administrator.', StackTrace.current);
        await _supabase.auth.signOut();
        return;
      }
      final profile = UserProfile.fromJson(profileData);
      if (!profile.isActive) {
        state = AsyncValue.error('Your account has been deactivated. Contact your administrator.', StackTrace.current);
        await _supabase.auth.signOut();
        return;
      }
      state = AsyncValue.data(profile);
    } on AuthException catch (e) {
      // Map Supabase error codes to friendly messages
      String message;
      switch (e.message.toLowerCase()) {
        case 'invalid login credentials':
        case 'invalid_credentials':
          message = 'Invalid email or password. Please try again.';
          break;
        case 'email not confirmed':
          message = 'Email not confirmed. Contact your administrator.';
          break;
        case 'too many requests':
          message = 'Too many login attempts. Please wait and try again.';
          break;
        default:
          message = e.message;
      }
      state = AsyncValue.error(message, StackTrace.current);
    } catch (e) {
      state = AsyncValue.error('An unexpected error occurred: ${e.toString()}', StackTrace.current);
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> loadCurrentProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final profileData = await _supabase
          .from(SupabaseConstants.userProfiles)
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profileData == null) {
        state = const AsyncValue.data(null);
      } else {
        state = AsyncValue.data(UserProfile.fromJson(profileData));
      }
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>((ref) {
  final notifier = AuthNotifier(ref);
  notifier.loadCurrentProfile();
  return notifier;
});
