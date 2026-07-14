import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_supabase_datasource.dart';
import 'package:zopiqnow/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<AuthDataSource> authDataSourceProvider = Provider<AuthDataSource>(
  (Ref ref) => const AuthSupabaseDataSource(),
);

/// Repository binding — the seam the UI depends on (SAD 7.4).
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepositoryImpl(ref.watch(authDataSourceProvider)),
    );

/// Where the user stands with respect to authentication.
///
/// [AuthUnknown] is not a loading spinner — it is the window between launch and
/// the session read completing, during which the router must not redirect. Send
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
      final AuthUser? user = await ref
          .read(authRepositoryProvider)
          .restoreSession();
      state = user == null ? const AuthSignedOut() : AuthSignedIn(user);
    } on Object {
      // A Keystore read can fail outright — a corrupted keyset, or an OEM with a
      // broken provider. Signed-out is recoverable (the user logs in again);
      // staying [AuthUnknown] would strand them on the splash forever (Rule 1.6).
      state = const AuthSignedOut();
    }
  }

  Future<void> sendEmailOtp(String email) =>
      ref.read(authRepositoryProvider).sendEmailOtp(email);

  /// Throws [AuthFailure] on a bad/expired code — the OTP screen renders it.
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final AuthUser user = await ref
        .read(authRepositoryProvider)
        .verifyEmailOtp(email: email, code: code);
    state = AuthSignedIn(user);
  }

  /// Throws [GoogleSignInCancelled] when the user dismisses the sheet — the
  /// email screen swallows that one; everything else it renders.
  Future<void> signInWithGoogle() async {
    final AuthUser user = await ref
        .read(authRepositoryProvider)
        .signInWithGoogle();
    state = AuthSignedIn(user);
  }

  /// The delivery number. Asked for at checkout, where it is first needed, not
  /// as a fourth screen between the user and their food.
  Future<void> setPhone(String phone) async {
    final AuthUser user = await ref.read(authRepositoryProvider).setPhone(phone);
    state = AuthSignedIn(user);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthSignedOut();
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
