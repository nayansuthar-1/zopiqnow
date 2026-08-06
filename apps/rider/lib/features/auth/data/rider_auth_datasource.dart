import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/app/env.dart';
import 'package:zopiq_rider/core/observability/crash_reporter.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider_kyc.dart';

/// Sign-in, and the question that follows it: *do you ride for us?*
///
/// Two separate things, in that order — exactly as in the vendor app. Supabase
/// authenticates an email address; `delivery_partners` says whether that address
/// is anybody at Zopiqnow. A person can pass the first and fail the second, and
/// this app has a screen for precisely that.
abstract interface class RiderAuthDataSource {
  /// Mails a 6-digit code.
  ///
  /// Sent to *any* address that asks, without checking first whether it belongs
  /// to a partner — deliberately, and for the reason the vendor app gives at
  /// length: a "you are not a partner" answer *before* the code is sent is an
  /// oracle. Anyone could sit and type addresses until one came back different,
  /// and the ones that come back different belong to people who can see where
  /// customers live.
  Future<void> sendEmailOtp(String email);

  /// Verifies the code and resolves who this is. Null when the code was right
  /// and the person simply does not ride for Zopiqnow; throws [RiderAuthFailure]
  /// when the code was wrong.
  Future<Rider?> verifyEmailOtp({required String email, required String code});

  /// Signs in with the device's Google account, then answers the same question
  /// [verifyEmailOtp] does.
  ///
  /// **The gate is unchanged.** Google says who you are; `delivery_partners`
  /// says whether that is anybody who rides for Zopiqnow. A new front door, not
  /// a new authority — an account with no row there still reads nothing.
  ///
  /// Returns the address Google vouched for alongside the rider, because on the
  /// null branch the caller has to name it and, unlike the OTP path, never had
  /// it. Throws [RiderGoogleCancelled] when the sheet was dismissed — a choice,
  /// not a failure — and [RiderAuthFailure] for everything else.
  Future<({Rider? rider, String email})> signInWithGoogle();

  Future<Rider?> restoreSession();

  /// Where this rider stands on documents (0080). Status and a sentence — never
  /// the documents themselves, which no rider-side screen can reach.
  Future<RiderKyc> fetchKyc();

  Future<void> signOut();
}

class RiderAuthFailure implements Exception {
  const RiderAuthFailure([
    this.message = 'That code didn\'t work. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'RiderAuthFailure: $message';
}

/// The account sheet was dismissed. Its own type because it is not an error: the
/// screen says nothing at all, where a [RiderAuthFailure] would put a red
/// sentence under a button in answer to somebody changing their mind.
class RiderGoogleCancelled implements Exception {
  const RiderGoogleCancelled();
}

class RiderAuthSupabaseDataSource implements RiderAuthDataSource {
  const RiderAuthSupabaseDataSource();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> sendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email.trim(),
        // A rider's auth account is created on first sign-in like anyone
        // else's. It grants nothing: authority comes from `delivery_partners`,
        // and an account with no row there can read exactly nothing.
        shouldCreateUser: true,
      );
    } on AuthException catch (e) {
      // Supabase writes these for humans — "For security purposes, you can only
      // request this after 54 seconds" is the actual answer, and the rider can
      // act on it. The screen used to replace every failure with one sentence
      // that said nothing, which is how a missing INTERNET permission looked
      // identical to a rate limit for four phases.
      throw RiderAuthFailure(e.message);
    }
  }

  @override
  Future<Rider?> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.email,
      );
    } on AuthException catch (e) {
      throw RiderAuthFailure(e.message);
    }
    return _resolveRider();
  }

  @override
  Future<({Rider? rider, String email})> signInWithGoogle() async {
    try {
      await _ensureGoogleReady();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      // The id token *is* the credential. Supabase verifies its signature and
      // audience against the Google client it is configured with, so nothing
      // here has to be trusted: a forged token fails at the server.
      final String? idToken = account.authentication.idToken;
      if (idToken == null) throw const RiderAuthFailure(_googleFailed);

      // Experimental in gotrue 2.10, and the only way to exchange a *native* id
      // token for a session. The version is pinned, so it cannot move under us.
      // ignore: experimental_member_use
      final AuthResponse response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      if (response.user == null) throw const RiderAuthFailure(_googleFailed);
    } on GoogleSignInException catch (e, stack) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const RiderGoogleCancelled();
      }
      // One sentence on screen; which failure it was goes here. Otherwise
      // telling a wrong signing certificate (`Invalid key value:
      // <sha1>:com.siteonlab.zopiq_rider`) from a dead network needs `adb
      // logcat` on a device you are holding — no use for a rider at a kerb.
      _reportGoogleFailure(e, stack, 'sign-in failed (${e.code.name})');
      throw const RiderAuthFailure(_googleFailed);
    } on AuthException catch (e, stack) {
      // Google vouched and Supabase would not take it: `aud` mismatch, or the
      // provider is off. A different bug, identical on screen.
      _reportGoogleFailure(e, stack, 'id token rejected (${e.message})');
      throw const RiderAuthFailure(_googleFailed);
    } on RiderGoogleCancelled {
      rethrow;
    } on RiderAuthFailure {
      rethrow;
    } on Object catch (e, stack) {
      // `_ensureGoogleReady` raises here — no Play services, a plugin that never
      // registered. Uncaught, the button stops with nothing said.
      _reportGoogleFailure(e, stack, 'sign-in failed unexpectedly');
      throw const RiderAuthFailure(_googleFailed);
    }

    // Outside the try: a *partner* lookup that fails is not a Google problem,
    // and reporting it as one sends somebody hunting a certificate over a
    // dropped connection.
    return (
      rider: await _resolveRider(),
      email: _client.auth.currentUser?.email ?? '',
    );
  }

  static const String _googleFailed =
      'Google sign-in didn\'t work. Try again, or use your email.';

  /// One initialise per process, and never a cached failure — caching one would
  /// leave the button dead for the rest of the run over a transient fault.
  static Future<void>? _googleReady;

  Future<void> _ensureGoogleReady() async {
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize(
        serverClientId: Env.googleWebClientId,
      ));
    } on Object {
      _googleReady = null;
      rethrow;
    }
  }

  static void _reportGoogleFailure(Object e, StackTrace stack, String what) {
    debugPrint('Google $what: $e');
    CrashReporter.recordHandled(e, stack, reason: 'Google $what');
  }

  @override
  Future<Rider?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    return _resolveRider();
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// `my_kyc` returns a table, so PostgREST sends a one-row array.
  ///
  /// A failure reads as "still being checked" rather than propagating. This is a
  /// status card on a profile screen, and a rider who cannot reach the network
  /// should see the cautious answer — not a red box, and certainly not an
  /// optimistic one, since the database is the thing actually enforcing it.
  @override
  Future<RiderKyc> fetchKyc() async {
    try {
      final List<dynamic> rows = await _client.rpc<List<dynamic>>('my_kyc');
      if (rows.isEmpty) return _unknown;
      return RiderKyc.fromJson(rows.first as Map<String, dynamic>);
    } on Object {
      return _unknown;
    }
  }

  static const RiderKyc _unknown = RiderKyc(
    status: 'pending',
    blockedReason: 'We couldn\'t check your documents just now.',
    daysToExpiry: null,
    nothingFiled: false,
  );

  /// One round trip, unlike the vendor's three.
  ///
  /// `delivery_partners` carries the rider's own name and phone, and 0025 gives
  /// them a select policy over exactly one row — their own. So the row *is* the
  /// answer, and no `staff_restaurant_id()`-style function is needed to keep the
  /// rest of the table hidden: the policy already does it.
  ///
  /// The `is_active` filter is not decoration. `delivery_partner_email()` — which
  /// every RPC in 0025 opens with — returns null for a deactivated partner, but
  /// the *select policy* has no such clause. Without this the app would let a
  /// deactivated rider all the way in and then refuse every single thing they
  /// tried to do. Filtering here makes the app's idea of "you ride for us" the
  /// same as the database's, so they land on the not-a-partner screen instead.
  Future<Rider?> _resolveRider() async {
    final String? email = _client.auth.currentUser?.email;
    if (email == null) return null;

    final Map<String, dynamic>? row = await _client
        .from('delivery_partners')
        // The two rating columns ride along on the read that was already being
        // made (0062). They need no policy of their own — the row is the
        // rider's, and this is the rider.
        .select('email, name, phone, rating, rating_count')
        .eq('is_active', true)
        .maybeSingle();

    // No row means authenticated, and nobody. Not an error — a screen.
    if (row == null) return null;

    return Rider(
      email: row['email'] as String? ?? email,
      name: row['name'] as String? ?? 'Partner',
      phone: row['phone'] as String? ?? '',
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (row['rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}
