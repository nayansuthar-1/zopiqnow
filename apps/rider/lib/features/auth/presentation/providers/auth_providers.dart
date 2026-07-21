import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_rider/features/auth/data/rider_auth_datasource.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';

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
