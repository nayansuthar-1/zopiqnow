import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// The signed-in vendor, or null — for no session, or a session belonging to
  /// someone who is not staff.
  Future<Vendor?> restoreSession();

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
  Future<Vendor?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    return _resolveVendor();
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Two round trips, because there is no honest way to make it one.
  ///
  /// `restaurant_staff` is not readable through the API — deliberately, so that
  /// no one can enumerate which addresses run which kitchens. What is exposed is
  /// `staff_restaurant_id()`, which answers only about the caller. The name then
  /// comes from `restaurants`, which the caller may read *because* they are
  /// staff (the policy in 0009 lets them see their own row even when it is
  /// inactive — a delisted vendor still has to be told something).
  Future<Vendor?> _resolveVendor() async {
    final User? user = _client.auth.currentUser;
    final String? email = user?.email;
    if (email == null) return null;

    final String? restaurantId = await _client.rpc<String?>(
      'staff_restaurant_id',
    );
    if (restaurantId == null) return null;

    final Map<String, dynamic>? row = await _client
        .from('restaurants')
        .select('name')
        .eq('id', restaurantId)
        .maybeSingle();

    return Vendor(
      email: email,
      restaurantId: restaurantId,
      // The restaurant is referenced by `restaurant_staff` with a foreign key, so
      // a staff row without a restaurant cannot exist. If the read comes back
      // empty anyway, the id is still the truth and the name is decoration.
      restaurantName: row?['name'] as String? ?? 'Your restaurant',
    );
  }
}
