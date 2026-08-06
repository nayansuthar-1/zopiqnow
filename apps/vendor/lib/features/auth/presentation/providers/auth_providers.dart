import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/data/vendor_auth_datasource.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<VendorAuthDataSource> vendorAuthDataSourceProvider =
    Provider<VendorAuthDataSource>(
      (Ref ref) => const VendorAuthSupabaseDataSource(),
    );

/// Where the person holding the tablet stands.
///
/// Four states, not three, and the fourth is the interesting one: [NotStaff] is
/// a *successfully authenticated* user who does not work at a restaurant. They
/// are not signed out — they proved they own that mailbox — and they are not
/// signed in either, because there is nothing here for them. Collapsing that
/// into "signed out" would bounce them back to a login screen that would let
/// them log in again, forever.
sealed class VendorAuthState {
  const VendorAuthState();
}

/// The window between launch and the Keystore read returning. The splash renders
/// it. Redirecting during it would throw a signed-in kitchen back to the login
/// screen on every cold start.
class AuthUnknown extends VendorAuthState {
  const AuthUnknown();
}

class AuthSignedOut extends VendorAuthState {
  const AuthSignedOut();
}

class AuthNotStaff extends VendorAuthState {
  const AuthNotStaff(this.email);

  final String email;
}

class AuthSignedIn extends VendorAuthState {
  const AuthSignedIn(this.vendor);

  final Vendor vendor;
}

/// Owns the session. Synchronous state, because `GoRouter.redirect` is
/// synchronous and cannot await an answer to "who is this?".
class VendorAuthController extends Notifier<VendorAuthState> {
  @override
  VendorAuthState build() {
    unawaited(_restore());
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    try {
      final Vendor? vendor = await ref
          .read(vendorAuthDataSourceProvider)
          .restoreSession();
      state = vendor == null ? const AuthSignedOut() : AuthSignedIn(vendor);
    } on Object {
      // A Keystore read can fail outright — a corrupted keyset, an OEM with a
      // broken provider. Signed-out is recoverable; staying [AuthUnknown] would
      // strand the kitchen on a splash screen forever.
      state = const AuthSignedOut();
    }
  }

  Future<void> sendEmailOtp(String email) =>
      ref.read(vendorAuthDataSourceProvider).sendEmailOtp(email);

  /// Google sign-in, landing in exactly the same three states the OTP path does.
  ///
  /// A Google account that is nobody's staff is [AuthNotStaff], not an error —
  /// the same distinction the OTP path draws, because "wrong code" and "not a
  /// partner" are different conversations and so are "Google failed" and "you
  /// don't work here".
  ///
  /// [VendorGoogleCancelled] is left to propagate: the screen swallows it, since
  /// dismissing the account sheet deserves no message at all.
  Future<void> signInWithGoogle() async {
    final ({Vendor? vendor, String email}) result = await ref
        .read(vendorAuthDataSourceProvider)
        .signInWithGoogle();
    // The address Google vouched for, not one that was typed.
    state = result.vendor == null
        ? AuthNotStaff(result.email)
        : AuthSignedIn(result.vendor!);
  }

  /// Throws [VendorAuthFailure] on a bad or expired code — the OTP screen
  /// renders the message. A *valid* code for a non-staff address is not a
  /// failure and does not throw: it lands on [AuthNotStaff], which is a screen,
  /// not an error.
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final Vendor? vendor = await ref
        .read(vendorAuthDataSourceProvider)
        .verifyEmailOtp(email: email, code: code);
    state = vendor == null ? AuthNotStaff(email) : AuthSignedIn(vendor);
  }

  /// Open or close the kitchen. Optimistic: the switch flips first so a kitchen
  /// mid-rush is not made to wait on a round trip, and the write confirms it. A
  /// failure puts the state back and returns a sentence, exactly as the menu's
  /// availability switch does — and for the same reason, a screen that says
  /// "closed" while orders still arrive is the one lie this app must not tell.
  ///
  /// A no-op when not signed in: there is no restaurant to open or close.
  Future<String?> setAcceptingOrders(bool accepting, {String reason = ''}) async {
    final VendorAuthState current = state;
    if (current is! AuthSignedIn) return null;
    if (current.vendor.acceptingOrders == accepting) return null;

    // Mirrors what 0068 will write: the reason on the way down, and nothing on
    // the way back up. Guessing wrong here would leave the banner disagreeing
    // with the row until the next sign-in.
    state = AuthSignedIn(
      current.vendor.copyWith(
        acceptingOrders: accepting,
        pauseReason: accepting ? '' : reason,
      ),
    );
    try {
      await ref
          .read(vendorAuthDataSourceProvider)
          .setAcceptingOrders(accepting, reason: reason);
      return null;
    } on Object {
      state = current;
      return accepting
          ? 'We couldn\'t reopen the kitchen. Please try again.'
          : 'We couldn\'t pause orders. Please try again.';
    }
  }

  /// Reflect a renamed restaurant in the session, so the queue header stops
  /// showing the old name the moment the profile is saved — without a re-login
  /// or a refetch. A no-op when not signed in.
  void applyRestaurantName(String name) {
    final VendorAuthState current = state;
    if (current is AuthSignedIn) {
      state = AuthSignedIn(current.vendor.copyWith(restaurantName: name));
    }
  }

  Future<void> signOut() async {
    await ref.read(vendorAuthDataSourceProvider).signOut();
    state = const AuthSignedOut();
  }
}

final NotifierProvider<VendorAuthController, VendorAuthState>
vendorAuthControllerProvider =
    NotifierProvider<VendorAuthController, VendorAuthState>(
      VendorAuthController.new,
    );

/// The signed-in vendor, or null. What the queue filters on.
final Provider<Vendor?> vendorProvider = Provider<Vendor?>((Ref ref) {
  final VendorAuthState state = ref.watch(vendorAuthControllerProvider);
  return state is AuthSignedIn ? state.vendor : null;
});
