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

  /// Signs in with a Google account, or throws [GoogleSignInCancelled] if the
  /// user backs out of the sheet.
  Future<AuthUser> signInWithGoogle();

  /// Writes the given profile fields and returns the updated user. A field left
  /// out is left alone — the transport cannot tell "unchanged" from "cleared",
  /// so it never has to: only what the caller names is written.
  Future<AuthUser> saveProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
  });

  /// Closes the signed-in account for good, then ends the session.
  ///
  /// Throws [AccountDeletionRefused] with the database's own sentence when
  /// something stands in the way — an order still on its way, or a login that a
  /// restaurant or a rider also uses.
  Future<void> deleteAccount();

  Future<void> signOut();
}
