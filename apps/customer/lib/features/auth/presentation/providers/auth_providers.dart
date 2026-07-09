import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// Data source binding. Overridden in tests to drop the fake network latency.
final Provider<AuthMockDataSource> authDataSourceProvider =
    Provider<AuthMockDataSource>((Ref ref) => AuthMockDataSource());

/// Repository binding — the seam the UI depends on (SAD 7.4).
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepositoryImpl(
        ref.watch(authDataSourceProvider),
        ref.watch(secureStoreProvider),
      ),
    );

/// Where the user stands with respect to authentication.
///
/// [AuthUnknown] is not a loading spinner — it is the window between launch and
/// the Keystore read completing, during which the router must not redirect. Send
/// a signed-in user to `/login` for even one frame and their deep link is gone.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AuthUser user;
}

/// Owns the session. Synchronous state, because `GoRouter.redirect` is
/// synchronous and has to answer "is this user signed in?" without awaiting.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Fire-and-forget by design: `build` cannot await, and the router already
    // renders a splash for [AuthUnknown] until this lands.
    unawaited(_restore());
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    try {
      final AuthSession? session = await ref
          .read(authRepositoryProvider)
          .restoreSession();
      state = session == null
          ? const AuthSignedOut()
          : AuthSignedIn(session.user);
    } on Object {
      // A Keystore read can fail outright — a corrupted keyset, or an OEM with a
      // broken provider. Signed-out is recoverable (the user logs in again);
      // staying [AuthUnknown] would strand them on the splash forever (Rule 1.6).
      state = const AuthSignedOut();
    }
  }

  Future<void> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).requestOtp(phone);

  /// Throws [AuthFailure] on a bad/expired code — the OTP screen renders it.
  Future<void> verifyOtp({required String phone, required String code}) async {
    final AuthSession session = await ref
        .read(authRepositoryProvider)
        .verifyOtp(phone: phone, code: code);
    state = AuthSignedIn(session.user);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthSignedOut();
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
