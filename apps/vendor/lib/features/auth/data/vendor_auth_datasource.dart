import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/app/env.dart';
import 'package:zopiq_vendor/core/observability/crash_reporter.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';

/// Sign-in, and the question that follows it: *do you work here?*
///
/// Those are two separate things, and the order matters. Supabase authenticates
/// an email address; `restaurant_staff` says whether that address is anybody at
/// Zopiqnow. A person can pass the first and fail the second, and the app has a
/// screen for exactly that.
abstract interface class VendorAuthDataSource {
  /// Mails a 6-digit code.
  ///
  /// Sent to *any* address that asks, without first checking whether it is staff
  /// — and that is deliberate. A "this email is not a partner" response before
  /// the code is sent would be an oracle: anyone could sit and type addresses
  /// until they found one that worked, and the ones that work belong to the
  /// people who can accept orders. So the check happens after sign-in, where the
  /// answer costs an attacker a mailbox they already control.
  Future<void> sendEmailOtp(String email);

  /// Verifies the code and resolves who this is.
  ///
  /// Returns null when the code was right and the person is simply not staff.
  /// Throws [VendorAuthFailure] when the code was wrong — a distinction the UI
  /// leans on hard, because "wrong code" and "not a partner" are different
  /// conversations.
  Future<Vendor?> verifyEmailOtp({required String email, required String code});

  /// Signs in with the device's Google account, then answers the same question
  /// [verifyEmailOtp] does: null when this is a real Google account belonging to
  /// nobody who works here.
  ///
  /// **The gate is unchanged.** Google says who you are; `restaurant_staff` says
  /// whether that is anyone at Zopiqnow. A new front door, not a new authority —
  /// an account with no row there can still read exactly nothing.
  ///
  /// Throws [VendorGoogleCancelled] when the account sheet was dismissed, which
  /// is a choice and not a failure, and [VendorAuthFailure] for everything else.
  ///
  /// Returns the address Google vouched for alongside the vendor, because on the
  /// null branch the caller has to name it — "zopiq@gmail.com isn't a partner" —
  /// and unlike the OTP path it never had it to begin with. Reading it back off
  /// the Supabase client in the provider layer would put the SDK somewhere tests
  /// deliberately keep it out of.
  Future<({Vendor? vendor, String email})> signInWithGoogle();

  /// The signed-in vendor, or null — for no session, or a session belonging to
  /// someone who is not staff.
  Future<Vendor?> restoreSession();

  /// Open or close the kitchen. Writes `restaurants.accepting_orders` for the
  /// caller's own restaurant through an RPC — never a direct table write, which
  /// RLS could not stop from reaching another column. Throws on failure so the
  /// controller can put the switch back.
  ///
  /// [reason] is what customers are shown while the kitchen is paused. It is
  /// ignored when reopening — Postgres clears the column itself (0068), so the
  /// caller does not have to remember to.
  Future<void> setAcceptingOrders(bool accepting, {String reason = ''});

  Future<void> signOut();
}

class VendorAuthFailure implements Exception {
  const VendorAuthFailure([
    this.message = 'That code didn\'t work. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'VendorAuthFailure: $message';
}

/// The account sheet was dismissed. Its own type because it is not an error:
/// the screen shows nothing at all, where a [VendorAuthFailure] would put a red
/// sentence under a button in answer to somebody changing their mind.
class VendorGoogleCancelled implements Exception {
  const VendorGoogleCancelled();
}

class VendorAuthSupabaseDataSource implements VendorAuthDataSource {
  const VendorAuthSupabaseDataSource();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> sendEmailOtp(String email) => _client.auth.signInWithOtp(
    email: email.trim(),
    // A vendor's auth account is created on first sign-in like anyone else's.
    // It grants nothing: authority comes from `restaurant_staff`, and an account
    // with no row there can read exactly nothing.
    shouldCreateUser: true,
  );

  @override
  Future<Vendor?> verifyEmailOtp({
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
      throw VendorAuthFailure(e.message);
    }

    return _resolveVendor();
  }

  @override
  Future<({Vendor? vendor, String email})> signInWithGoogle() async {
    try {
      await _ensureGoogleReady();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      // The id token *is* the credential. Supabase verifies its signature and
      // audience against the Google client it is configured with, so nothing
      // here has to be trusted: a forged token fails at the server, not in this
      // method.
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const VendorAuthFailure(_googleFailed);
      }

      // Experimental in gotrue 2.10, and the only way to exchange a *native* id
      // token for a session — the alternative is the browser OAuth flow, which
      // this app deliberately does not use. The version is pinned, so it cannot
      // change under us.
      // ignore: experimental_member_use
      final AuthResponse response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      if (response.user == null) throw const VendorAuthFailure(_googleFailed);
    } on GoogleSignInException catch (e, stack) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const VendorGoogleCancelled();
      }
      // One sentence on screen; which failure it actually was goes here. Without
      // it, telling a wrong signing certificate (`Invalid key value:
      // <sha1>:com.siteonlab.zopiq_vendor`) from a dead network needs `adb
      // logcat` on a device you happen to be holding — no use at all when a
      // restaurant reports it from their own counter.
      _reportGoogleFailure(e, stack, 'sign-in failed (${e.code.name})');
      throw const VendorAuthFailure(_googleFailed);
    } on AuthException catch (e, stack) {
      // Google vouched and Supabase would not take it: the `aud` does not match
      // the configured client, or the provider is off. A different bug from the
      // above and indistinguishable from it on screen.
      _reportGoogleFailure(e, stack, 'id token rejected (${e.message})');
      throw const VendorAuthFailure(_googleFailed);
    } on VendorGoogleCancelled {
      rethrow;
    } on VendorAuthFailure {
      rethrow;
    } on Object catch (e, stack) {
      // `_ensureGoogleReady` raises here — a device with no Play services, a
      // plugin that never registered. Uncaught, the button would simply stop
      // with nothing said and nothing shown.
      _reportGoogleFailure(e, stack, 'sign-in failed unexpectedly');
      throw const VendorAuthFailure(_googleFailed);
    }

    // Outside the try: a *staff* lookup that fails is not a Google problem, and
    // reporting it as one would send somebody hunting a certificate over a
    // dropped connection.
    return (
      vendor: await _resolveVendor(),
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
  Future<Vendor?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    return _resolveVendor();
  }

  @override
  Future<void> setAcceptingOrders(bool accepting, {String reason = ''}) =>
      _client.rpc<void>(
        'set_accepting_orders',
        params: <String, dynamic>{
          'p_accepting': accepting,
          'p_reason': reason,
        },
      );

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Three round trips, because there is no honest way to make it fewer.
  ///
  /// `restaurant_staff` is not readable through the API — deliberately, so that
  /// no one can enumerate which addresses run which kitchens. What is exposed is
  /// `staff_restaurant_id()` and its twin `staff_role()`, each of which answers
  /// only about the caller. The two are asked at once, since neither depends on
  /// the other. The name then comes from `restaurants`, which the caller may
  /// read *because* they are staff (the policy in 0009 lets them see their own
  /// row even when it is inactive — a delisted vendor still has to be told
  /// something).
  Future<Vendor?> _resolveVendor() async {
    final User? user = _client.auth.currentUser;
    final String? email = user?.email;
    if (email == null) return null;

    final List<String?> identity = await Future.wait<String?>(<Future<String?>>[
      _client.rpc<String?>('staff_restaurant_id'),
      _client.rpc<String?>('staff_role'),
    ]);
    final String? restaurantId = identity[0];
    if (restaurantId == null) return null;

    final Map<String, dynamic>? row = await _client
        .from('restaurants')
        .select('name, accepting_orders, pause_reason')
        .eq('id', restaurantId)
        .maybeSingle();

    return Vendor(
      email: email,
      restaurantId: restaurantId,
      // The restaurant is referenced by `restaurant_staff` with a foreign key, so
      // a staff row without a restaurant cannot exist. If the read comes back
      // empty anyway, the id is still the truth and the name is decoration.
      restaurantName: row?['name'] as String? ?? 'Your restaurant',
      // A missing read defaults to open — the queue is the safe place to fail:
      // better a kitchen that thinks it is open and refuses at `place_order` than
      // one shown closed when it is not. The database is the truth either way.
      acceptingOrders: row?['accepting_orders'] as bool? ?? true,
      pauseReason: row?['pause_reason'] as String? ?? '',
      role: StaffRole.fromDb(identity[1]),
    );
  }
}
