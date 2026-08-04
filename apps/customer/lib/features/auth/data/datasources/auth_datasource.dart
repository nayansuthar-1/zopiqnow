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

  /// Texts a 6-digit code to [phone], which must already be E.164 (`+91…`).
  ///
  /// Supabase owns the code at both ends — it generates it and it checks it.
  /// MSG91 only carries it, through the `send-sms-otp` Edge Function wired in as
  /// GoTrue's *Send SMS* hook. That split is the whole design: an SMS provider
  /// that could mint sessions would need the service-role key, and this one
  /// never sees anything but a phone number and six digits.
  Future<void> sendPhoneOtp(String phone);

  Future<AuthUser> verifyPhoneOtp({
    required String phone,
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
