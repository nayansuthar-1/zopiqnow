import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';

/// The auth transport. Supabase in the app, a fake in tests — a widget test has
/// no Supabase instance, and a plugin call in one throws.
abstract interface class AuthDataSource {
  /// The restored session's user, or null when signed out. Synchronous: the
  /// client restores the session during startup, before the first frame.
  AuthUser? currentUser();

  Future<void> sendEmailOtp(String email);

  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  });

  Future<AuthUser> setPhone(String phone);

  Future<void> signOut();
}
