import 'package:google_sign_in/google_sign_in.dart';
// Supabase exports an `AuthUser` of its own (an alias of `User`). Ours is the
// domain entity, so theirs is the one that gives way.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'package:zopiqnow/app/env.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// Supabase Auth, over email OTP and native Google sign-in.
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

  /// `GoogleSignIn.initialize` must run once before anything else, and only
  /// once. It is deliberately *not* called from `main`: nobody should pay a
  /// plugin round-trip on every cold start for a button most users never press.
  static Future<void>? _googleReady;

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
  Future<AuthUser> signInWithGoogle() async {
    try {
      await _ensureGoogleReady();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      // The id token *is* the credential. Supabase verifies its signature and
      // audience against the Google client it was configured with, which is why
      // nothing here has to be trusted: a forged token fails at the server, not
      // in this method.
      final String? idToken = account.authentication.idToken;
      if (idToken == null) throw const GoogleSignInFailure();

      // `signInWithIdToken` is marked experimental in gotrue 2.10, but it is the
      // only way to exchange a *native* id token for a session — the alternative
      // is the browser OAuth flow we deliberately did not take. Pinned version,
      // so it cannot change under us (Rule 4).
      // ignore: experimental_member_use
      final AuthResponse response = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      final User? user = response.user;
      if (user == null) throw const GoogleSignInFailure();
      return _toDomain(user);
    } on GoogleSignInException catch (e) {
      // Dismissing the account sheet is a choice, not a failure. Everything
      // else — no Play services, a certificate that does not match the OAuth
      // client, no network — is one bug report away and reads the same to the
      // user: it didn't work, use email.
      throw e.code == GoogleSignInExceptionCode.canceled
          ? const GoogleSignInCancelled()
          : const GoogleSignInFailure();
    } on AuthException {
      throw const GoogleSignInFailure();
    }
  }

  Future<void> _ensureGoogleReady() async {
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize(
        serverClientId: Env.googleWebClientId,
      ));
    } on Object {
      // Never cache a failed initialise: doing so would leave the button dead
      // for the rest of the process over what may have been a transient fault.
      _googleReady = null;
      rethrow;
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
