import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';

/// Contract for phone-OTP authentication (SAD 9.1 / 9.3).
///
/// Mock today, HTTP at Step 7. The presentation layer depends only on this, so
/// swapping the data source must not touch a widget.
abstract interface class AuthRepository {
  /// Restores a persisted session, or null when signed out.
  ///
  /// Never throws: a corrupt or unreadable session is treated as signed out,
  /// because a user who cannot read their token must still reach the login
  /// screen rather than a crash on launch.
  Future<AuthSession?> restoreSession();

  /// Sends a 6-digit OTP to [phone] (E.164).
  ///
  /// Throws [AuthFailure] when the number is rejected or delivery fails.
  Future<void> requestOtp(String phone);

  /// Exchanges [code] for a session and persists it.
  ///
  /// Throws [InvalidOtp] on a wrong code, [OtpExpired] once the 5-minute TTL
  /// has passed, and [TooManyOtpAttempts] after the attempt cap.
  Future<AuthSession> verifyOtp({required String phone, required String code});

  /// Clears the persisted session. Server-side revocation lands with the API.
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
