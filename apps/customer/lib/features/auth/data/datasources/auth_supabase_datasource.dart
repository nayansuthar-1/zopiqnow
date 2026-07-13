// Supabase exports an `AuthUser` of its own (an alias of `User`). Ours is the
// domain entity, so theirs is the one that gives way.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// Supabase Auth, over email OTP.
///
/// The 6-digit code is a template decision on the dashboard, not a different
/// endpoint: the same `signInWithOtp` mails a magic link or a code depending on
/// whether the template renders `{{ .Token }}`. Ours renders the code.
class AuthSupabaseDataSource implements AuthDataSource {
  const AuthSupabaseDataSource();

  /// Resolved per call, not injected: `Supabase.instance` only exists after
  /// `main` initialises it, and providers are built before that on a cold start.
  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Where the delivery number lives — see [AuthRepository.setPhone].
  static const String phoneMetadataKey = 'delivery_phone';

  @override
  AuthUser? currentUser() {
    final User? user = _auth.currentUser;
    return user == null ? null : _toDomain(user);
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    try {
      await _auth.signInWithOtp(email: email);
    } on AuthException catch (e) {
      throw _sendFailure(e);
    }
  }

  @override
  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    try {
      final AuthResponse response = await _auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      final User? user = response.user;
      if (user == null) throw const InvalidOtp();
      return _toDomain(user);
    } on AuthException catch (e) {
      throw _verifyFailure(e);
    }
  }

  @override
  Future<AuthUser> setPhone(String phone) async {
    final UserResponse response = await _auth.updateUser(
      UserAttributes(data: <String, dynamic>{phoneMetadataKey: phone}),
    );
    // `updateUser` either throws or returns the updated user.
    return _toDomain(response.user!);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AuthUser _toDomain(User user) => AuthUser(
    id: user.id,
    // A user who signed in with an email always has one. The field is nullable
    // because Supabase also allows phone-only and anonymous users.
    email: user.email ?? '',
    phone: user.userMetadata?[phoneMetadataKey] as String?,
  );

  /// Supabase's own message ("Error sending confirmation email") describes our
  /// SMTP, not the user's problem, so only the rate limit is worth relaying.
  static AuthFailure _sendFailure(AuthException e) =>
      _isRateLimit(e) ? const TooManyOtpAttempts() : const OtpDeliveryFailure();

  static AuthFailure _verifyFailure(AuthException e) {
    if (_isRateLimit(e)) return const TooManyOtpAttempts();
    if (e.code == 'otp_expired') return const OtpExpired();
    // Supabase answers a wrong code and an expired one with the same 403; the
    // code above is the only thing that separates them. Anything left is "wrong
    // code", which is both the common case and the safe thing to say.
    return const InvalidOtp();
  }

  static bool _isRateLimit(AuthException e) =>
      e.statusCode == '429' ||
      e.code == 'over_email_send_rate_limit' ||
      e.code == 'over_request_rate_limit';
}
