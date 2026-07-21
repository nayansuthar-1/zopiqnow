import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';

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

  Future<Rider?> restoreSession();

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

class RiderAuthSupabaseDataSource implements RiderAuthDataSource {
  const RiderAuthSupabaseDataSource();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<void> sendEmailOtp(String email) => _client.auth.signInWithOtp(
    email: email.trim(),
    // A rider's auth account is created on first sign-in like anyone else's. It
    // grants nothing: authority comes from `delivery_partners`, and an account
    // with no row there can read exactly nothing.
    shouldCreateUser: true,
  );

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
  Future<Rider?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    return _resolveRider();
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

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
        .select('email, name, phone')
        .eq('is_active', true)
        .maybeSingle();

    // No row means authenticated, and nobody. Not an error — a screen.
    if (row == null) return null;

    return Rider(
      email: row['email'] as String? ?? email,
      name: row['name'] as String? ?? 'Partner',
      phone: row['phone'] as String? ?? '',
    );
  }
}
