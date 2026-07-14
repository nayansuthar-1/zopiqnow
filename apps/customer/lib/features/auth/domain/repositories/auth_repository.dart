import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';

/// Contract for email-OTP authentication (SAD 9.1 / 9.3).
///
/// Email, not SMS: there is no SMS provider yet. The phone-OTP contract is
/// preserved in `AuthMockDataSource` — when an SMS provider lands, the transport
/// swaps and these screens barely move.
abstract interface class AuthRepository {
  /// Restores a persisted session, or null when signed out.
  ///
  /// Never throws: a corrupt or unreadable session is treated as signed out,
  /// because a user who cannot read their token must still reach the login
  /// screen rather than a crash on launch.
  Future<AuthUser?> restoreSession();

  /// Emails a 6-digit code to [email], creating the account if it is new.
  ///
  /// Throws [OtpDeliveryFailure] when the address is rejected or the mail cannot
  /// be sent, and [TooManyOtpAttempts] once the send rate limit is hit.
  Future<void> sendEmailOtp(String email);

  /// Exchanges [code] for a session.
  ///
  /// Throws [InvalidOtp] on a wrong code, [OtpExpired] once the code's TTL has
  /// passed, and [TooManyOtpAttempts] after the attempt cap.
  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  });

  /// Signs in with a Google account, creating it if it is new.
  ///
  /// Throws [GoogleSignInCancelled] when the user dismisses the account sheet —
  /// which is not an error and must not be shown as one — and
  /// [GoogleSignInFailure] when the sign-in itself fails.
  Future<AuthUser> signInWithGoogle();

  /// Stores [phone] (E.164) against the signed-in user.
  ///
  /// It goes in the user's metadata, not Supabase's `phone` column: that column
  /// is for phone *sign-in*, and writing it starts an SMS verification we have no
  /// provider for. This is a delivery contact, not a credential.
  Future<AuthUser> setPhone(String phone);

  /// Ends the session — locally, and server-side where the transport allows.
  Future<void> signOut();
}

/// Domain-level auth failure. Carries a human message and nothing else — the
/// UI needs to render it, not to branch on transport details.
sealed class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class InvalidOtp extends AuthFailure {
  const InvalidOtp([super.message = 'That code is not right. Try again.']);
}

class OtpExpired extends AuthFailure {
  const OtpExpired([
    super.message = 'That code has expired. Request a new one.',
  ]);
}

class TooManyOtpAttempts extends AuthFailure {
  const TooManyOtpAttempts([
    super.message = 'Too many attempts. Request a new code.',
  ]);
}

class OtpDeliveryFailure extends AuthFailure {
  const OtpDeliveryFailure([
    super.message = 'We couldn\'t send your code. Check your connection.',
  ]);
}

/// The user closed the Google account sheet. A deliberate choice, not a fault:
/// the UI swallows this one rather than accusing them of an error.
class GoogleSignInCancelled extends AuthFailure {
  const GoogleSignInCancelled([super.message = 'Sign-in cancelled.']);
}

class GoogleSignInFailure extends AuthFailure {
  const GoogleSignInFailure([
    super.message = 'Google sign-in failed. Try again, or use your email.',
  ]);
}
