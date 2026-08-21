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

  /// Texts a 6-digit code to [phone] (E.164), creating the account if it is new.
  ///
  /// **A phone account is not the customer's email account.** Supabase keys a
  /// user on phone *or* email, so somebody who signed up with an address and
  /// later signs in with their number arrives as a different user id, with none
  /// of their orders, addresses or saved restaurants. Linking the two is a
  /// deliberate, separate piece of work and has not been done.
  ///
  /// Throws the same failures as [sendEmailOtp].
  Future<void> sendPhoneOtp(String phone);

  /// Exchanges [code] for a session, for the number [sendPhoneOtp] texted.
  Future<AuthUser> verifyPhoneOtp({
    required String phone,
    required String code,
  });

  /// Gets Google sign-in ready ahead of the tap that needs it, so the account
  /// sheet opens immediately instead of after a plugin round trip the user
  /// reads as a dead button. Never throws — see the data source.
  Future<void> prepareGoogleSignIn();

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
  ///
  /// Kept as its own method because checkout's intent really is "record the
  /// delivery number" and nothing else; it is [saveProfile] underneath, so there
  /// is still exactly one thing that writes this field.
  Future<AuthUser> setPhone(String phone);

  /// Writes the profile fields the customer edited and returns the updated user.
  ///
  /// A field left out is left alone. There is deliberately no way to *clear* a
  /// field through this method: nothing in the UI offers it, and a null that
  /// means "erase this" in one call and "don't touch this" in another is how you
  /// wipe somebody's phone number by saving their date of birth.
  Future<AuthUser> saveProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
  });

  /// Closes the account permanently, then ends the session.
  ///
  /// There is no undo and no grace period: when this returns, the login, the
  /// saved addresses, the saved restaurants, the push tokens and the
  /// notifications are gone, and the orders that had to be kept for tax and for
  /// the restaurants' settlements no longer name anybody.
  ///
  /// Throws [AccountDeletionRefused] when something stands in the way — an order
  /// still on its way, or a login a restaurant or delivery partner also uses.
  Future<void> deleteAccount();

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

/// The database refused to close the account, and said why in its own words.
///
/// Every one of its refusals is temporary or resolvable — an order that has to
/// finish arriving, or a login that support has to unpick from a restaurant's —
/// so the message is shown as-is rather than being translated into an apology
/// that says less.
class AccountDeletionRefused extends AuthFailure {
  const AccountDeletionRefused([
    super.message = 'We couldn\'t delete your account. Please try again.',
  ]);
}

/// The session went away underneath a screen that needed one — a token that
/// could not refresh, or a sign-out in another tab of the same account. The
/// profile screen catches it and says so rather than saving into nothing.
class NotSignedIn extends AuthFailure {
  const NotSignedIn([
    super.message = 'You\'re signed out. Log in again to save this.',
  ]);
}
