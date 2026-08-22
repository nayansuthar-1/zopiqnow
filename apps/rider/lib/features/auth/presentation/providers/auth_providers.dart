import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_rider/features/auth/data/rider_auth_datasource.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider_kyc.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<RiderAuthDataSource> riderAuthDataSourceProvider =
    Provider<RiderAuthDataSource>(
      (Ref ref) => const RiderAuthSupabaseDataSource(),
    );

/// Where the person holding the phone stands.
///
/// Four states, and the fourth is the interesting one — the same shape the
/// vendor app uses, for the same reason. [AuthNotPartner] is a *successfully
/// authenticated* user who does not ride for Zopiqnow. They are not signed out
/// (they proved they own that mailbox) and not signed in (there is nothing here
/// for them). Collapsing that into "signed out" would bounce them to a login
/// screen that would happily let them log in again, forever.
sealed class RiderAuthState {
  const RiderAuthState();
}

/// The window between launch and the Keystore read returning. Redirecting during
/// it would throw a signed-in rider back to the login screen on every cold start.
class AuthUnknown extends RiderAuthState {
  const AuthUnknown();
}

class AuthSignedOut extends RiderAuthState {
  const AuthSignedOut();
}

class AuthNotPartner extends RiderAuthState {
  const AuthNotPartner(this.email);

  final String email;
}

class AuthSignedIn extends RiderAuthState {
  const AuthSignedIn(this.rider);

  final Rider rider;
}

/// Owns the session. Synchronous state, because `GoRouter.redirect` is
/// synchronous and cannot await an answer to "who is this?".
class RiderAuthController extends Notifier<RiderAuthState> {
  @override
  RiderAuthState build() {
    unawaited(_restore());
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    try {
      final Rider? rider = await ref
          .read(riderAuthDataSourceProvider)
          .restoreSession();
      state = rider == null ? const AuthSignedOut() : AuthSignedIn(rider);
    } on Object {
      // A Keystore read can fail outright — a corrupted keyset, an OEM with a
      // broken provider. Signed-out is recoverable; staying [AuthUnknown] would
      // strand the rider on a splash screen forever.
      state = const AuthSignedOut();
    }
  }

  Future<void> sendEmailOtp(String email) =>
      ref.read(riderAuthDataSourceProvider).sendEmailOtp(email);

  /// Throws [RiderAuthFailure] on a bad or expired code. A *valid* code for a
  /// non-partner address is not a failure and does not throw: it lands on
  /// [AuthNotPartner], which is a screen, not an error.
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final Rider? rider = await ref
        .read(riderAuthDataSourceProvider)
        .verifyEmailOtp(email: email, code: code);
    state = rider == null ? AuthNotPartner(email) : AuthSignedIn(rider);
  }

  /// Warms the Google plugin up so the button is ready when it is pressed.
  ///
  /// Deliberately not `await`ed by its caller and deliberately incapable of
  /// throwing: it is an optimisation, and an optimisation that can break a
  /// screen is not one. Leaves [state] alone — nobody is signing in yet.
  Future<void> prepareGoogleSignIn() =>
      ref.read(riderAuthDataSourceProvider).prepareGoogleSignIn();

  /// Google sign-in, landing in the same states the OTP path does.
  ///
  /// A Google account belonging to nobody who rides for us is [AuthNotPartner],
  /// not an error — the same distinction the OTP path draws, because "that code
  /// was wrong" and "you don't ride for us" are different conversations, and so
  /// are "Google failed" and "you don't ride for us".
  ///
  /// [RiderGoogleCancelled] propagates: the screen swallows it, since dismissing
  /// the account sheet deserves no message.
  Future<void> signInWithGoogle() async {
    final ({Rider? rider, String email}) result = await ref
        .read(riderAuthDataSourceProvider)
        .signInWithGoogle();
    // The address Google vouched for, not one that was typed.
    state = result.rider == null
        ? AuthNotPartner(result.email)
        : AuthSignedIn(result.rider!);
  }

  Future<void> signOut() async {
    await ref.read(riderAuthDataSourceProvider).signOut();
    state = const AuthSignedOut();
  }
}

final NotifierProvider<RiderAuthController, RiderAuthState>
riderAuthControllerProvider =
    NotifierProvider<RiderAuthController, RiderAuthState>(
      RiderAuthController.new,
    );

/// The signed-in rider, or null.
final Provider<Rider?> riderProvider = Provider<Rider?>((Ref ref) {
  final RiderAuthState state = ref.watch(riderAuthControllerProvider);
  return state is AuthSignedIn ? state.rider : null;
});

/// Where this rider stands on documents (0080, audit RID-002).
///
/// Read rather than watched-live: verification changes when an admin decides
/// something, which is minutes-to-days, not seconds. Invalidate it after any
/// refusal that mentions documents and it will be current when it matters.
final FutureProvider<RiderKyc> kycProvider = FutureProvider<RiderKyc>((Ref ref) {
  final Rider? rider = ref.watch(riderProvider);
  if (rider == null) {
    return Future<RiderKyc>.value(
      const RiderKyc(
        status: 'pending',
        blockedReason: null,
        daysToExpiry: null,
        nothingFiled: true,
      ),
    );
  }
  return ref.watch(riderAuthDataSourceProvider).fetchKyc();
});
