import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Supabase exports an `AuthUser` of its own (an alias of `User`). Ours is the
// domain entity, so theirs is the one that gives way.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'package:zopiqnow/app/env.dart';
import 'package:zopiqnow/core/observability/crash_reporter.dart';
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

  /// The profile keys, all namespaced, and that prefix is load-bearing.
  ///
  /// Google's claims land in this same `raw_user_meta_data` under `name`,
  /// `full_name`, `avatar_url` and `picture`, and gotrue merges them in at
  /// sign-in. Writing the customer's own name to `full_name` would put it in a
  /// field the provider believes it owns — so a customer who renamed themselves
  /// and then signed in with Google again could be silently renamed back. These
  /// four keys no provider writes, and every read below prefers them: **the
  /// provider's value is a default, the customer's is an answer.** Migration
  /// 0070 applies the same ordering to `restaurant_reviews`, the only place in
  /// the database that reads a customer's name.
  static const String nameMetadataKey = 'zopiq_full_name';
  static const String avatarMetadataKey = 'zopiq_avatar_url';
  static const String dobMetadataKey = 'zopiq_dob';
  static const String genderMetadataKey = 'zopiq_gender';

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
    } on GoogleSignInException catch (e, stack) {
      // Dismissing the account sheet is a choice, not a failure. Everything
      // else — no Play services, a certificate that does not match the OAuth
      // client, no network — is one bug report away and reads the same to the
      // user: it didn't work, use email.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInCancelled();
      }

      // The user gets one sentence; the thing that says *which* failure it was
      // goes here. Without this line the only way to tell a wrong signing
      // certificate (`Invalid key value: <sha1>:com.siteonlab.zopiqnow`) from a
      // dead network is `adb logcat` on a device you happen to be holding —
      // which cost five rounds of guessing the last time this broke, and is no
      // use at all for a customer reporting it from their own phone.
      _reportGoogleFailure(e, stack, 'sign-in failed (${e.code.name})');
      throw const GoogleSignInFailure();
    } on AuthException catch (e, stack) {
      // Google vouched for the user and Supabase would not take it: the `aud`
      // does not match `external_google_client_id`, the provider is disabled,
      // or the nonce check refused. A different bug entirely from the above,
      // and indistinguishable from it on screen.
      _reportGoogleFailure(
        e,
        stack,
        'id token rejected (${e.code ?? e.statusCode ?? 'no code'})',
      );
      throw const GoogleSignInFailure();
    } on AuthFailure {
      // Already ours and already the right shape — the two `null` guards above.
      rethrow;
    } on Object catch (e, stack) {
      // Anything else, and `_ensureGoogleReady` is the one that raises it: a
      // `PlatformException` from a device with no Play services, a plugin that
      // did not register. Uncaught, it escapes the screen's `on AuthFailure`
      // too, and the button simply stops with nothing said and nothing shown.
      _reportGoogleFailure(e, stack, 'sign-in failed unexpectedly');
      throw const GoogleSignInFailure();
    }
  }

  /// Both halves of the Google failure path record the same way: to Crashlytics
  /// for a customer's phone, and to the console for ours — Crashlytics collects
  /// nothing in a debug build (see `CrashReporter.enable`), which is precisely
  /// the build a developer chasing this is running.
  static void _reportGoogleFailure(Object e, StackTrace stack, String what) {
    debugPrint('Google $what: $e');
    CrashReporter.recordHandled(e, stack, reason: 'Google $what');
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
  Future<AuthUser> saveProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
  }) async {
    // Only the named fields go in the map. `updateUser` merges rather than
    // replaces, so an absent key leaves whatever was there — which is exactly
    // the "a field left out is left alone" contract, obtained for free instead
    // of by reading the old metadata back and re-sending it.
    final Map<String, dynamic> data = <String, dynamic>{
      nameMetadataKey: ?fullName,
      phoneMetadataKey: ?phone,
      avatarMetadataKey: ?avatarUrl,
      // Date only. `toIso8601String` would carry a midnight local time that
      // means nothing and reads differently either side of a timezone.
      if (dateOfBirth != null) dobMetadataKey: _formatDate(dateOfBirth),
      if (gender != null) genderMetadataKey: gender.name,
    };

    if (data.isEmpty) {
      // Nothing to write is not a round trip. Also stops an empty `updateUser`
      // from bumping the user row for no reason.
      final User? user = _auth.currentUser;
      if (user == null) throw const NotSignedIn();
      return _toDomain(user);
    }

    final UserResponse response = await _auth.updateUser(
      UserAttributes(data: data),
    );
    // `updateUser` either throws or returns the updated user.
    return _toDomain(response.user!);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    try {
      await Supabase.instance.client.rpc<void>('delete_my_account');
    } on PostgrestException catch (e) {
      // `P0001` is a rule we wrote, and its message was written for the person
      // reading it. Anything else is a bug or an outage and gets the generic
      // apology, because whatever Postgres says about it is not for them.
      if (e.code == _businessRuleErrorCode) throw AccountDeletionRefused(e.message);
      throw const AccountDeletionRefused();
    }

    // The account is gone; the session on this device is not, until we say so.
    // Signing out after the fact rather than before, because a sign-out first
    // would take away the credential the RPC authenticates with.
    //
    // Deliberately not awaited into failure: gotrue's sign-out revokes a token
    // that no longer has a user behind it, and an error there would be reported
    // to somebody whose account was in fact deleted successfully. Clearing what
    // is on this device is what matters, and that happens either way.
    try {
      await _auth.signOut();
    } on Object {
      // Nothing to do and nothing to say.
    }
  }

  /// Postgres raises `P0001` for the rules we wrote, with a message written for
  /// a human. Any other code is a bug or an outage.
  static const String _businessRuleErrorCode = 'P0001';

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static AuthUser _toDomain(User user) {
    final Map<String, dynamic> meta =
        user.userMetadata ?? const <String, dynamic>{};

    // Ours first, the identity provider's second, at every field it also
    // supplies. See the key declarations above for why that order is not a
    // preference.
    final String? name = _firstNonEmpty(<Object?>[
      meta[nameMetadataKey],
      meta['full_name'],
      meta['name'],
    ]);
    final String? avatar = _firstNonEmpty(<Object?>[
      meta[avatarMetadataKey],
      meta['avatar_url'],
      meta['picture'],
    ]);

    return AuthUser(
      id: user.id,
      // A user who signed in with an email always has one. The field is
      // nullable because Supabase also allows phone-only and anonymous users.
      email: user.email ?? '',
      phone: meta[phoneMetadataKey] as String?,
      fullName: name,
      avatarUrl: avatar,
      // `tryParse`, not `parse`: this is free-form JSON on a row the user can
      // write, and an unparseable date should cost the field, not the session.
      dateOfBirth: DateTime.tryParse(
        _firstNonEmpty(<Object?>[meta[dobMetadataKey]]) ?? '',
      ),
      gender: Gender.fromWire(
        _firstNonEmpty(<Object?>[meta[genderMetadataKey]]),
      ),
    );
  }

  /// The first value that is a non-blank string. Metadata is untyped JSON, so a
  /// number or a null in any of these slots is a value to skip, not to cast.
  static String? _firstNonEmpty(List<Object?> candidates) {
    for (final Object? c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

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
