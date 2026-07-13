import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

import '../../support/fake_auth_datasource.dart';

const String _email = 'diner@example.com';

void main() {
  group('email OTP', () {
    test('a correct code signs the user in', () async {
      final FakeAuthDataSource source = FakeAuthDataSource();
      final AuthRepositoryImpl repo = AuthRepositoryImpl(source);

      await repo.sendEmailOtp(_email);
      final AuthUser user = await repo.verifyEmailOtp(
        email: _email,
        code: FakeAuthDataSource.devCode,
      );

      expect(source.sentTo, <String>[_email]);
      expect(user.email, _email);
      // Sign-in is by email, so there is no number yet. Checkout asks for it.
      expect(user.phone, isNull);
    });

    test('a wrong code throws InvalidOtp and signs nobody in', () async {
      final FakeAuthDataSource source = FakeAuthDataSource();
      final AuthRepositoryImpl repo = AuthRepositoryImpl(source);

      await repo.sendEmailOtp(_email);

      await expectLater(
        repo.verifyEmailOtp(email: _email, code: '000000'),
        throwsA(isA<InvalidOtp>()),
      );
      expect(await repo.restoreSession(), isNull);
    });

    test('the attempt cap trips TooManyOtpAttempts', () async {
      final AuthRepositoryImpl repo = AuthRepositoryImpl(FakeAuthDataSource());
      await repo.sendEmailOtp(_email);

      // The 5th wrong attempt is the one that trips the cap.
      for (int i = 0; i < FakeAuthDataSource.maxAttempts - 1; i++) {
        await expectLater(
          repo.verifyEmailOtp(email: _email, code: '000000'),
          throwsA(isA<InvalidOtp>()),
        );
      }
      await expectLater(
        repo.verifyEmailOtp(email: _email, code: '000000'),
        throwsA(isA<TooManyOtpAttempts>()),
      );
      // Even the right code is refused once the challenge is locked out.
      await expectLater(
        repo.verifyEmailOtp(email: _email, code: FakeAuthDataSource.devCode),
        throwsA(isA<TooManyOtpAttempts>()),
      );
    });

    test('a code issued for another address is refused', () async {
      final AuthRepositoryImpl repo = AuthRepositoryImpl(FakeAuthDataSource());
      await repo.sendEmailOtp('someone@example.com');

      await expectLater(
        repo.verifyEmailOtp(email: _email, code: FakeAuthDataSource.devCode),
        throwsA(isA<OtpExpired>()),
      );
    });
  });

  group('session', () {
    test('restoreSession returns null when signed out', () async {
      expect(
        await AuthRepositoryImpl(FakeAuthDataSource()).restoreSession(),
        isNull,
      );
    });

    test('restoreSession returns the user Supabase restored', () async {
      const AuthUser user = AuthUser(id: 'usr_1', email: _email);
      final AuthRepositoryImpl repo = AuthRepositoryImpl(
        FakeAuthDataSource(signedInAs: user),
      );

      expect((await repo.restoreSession())?.email, _email);
    });

    test('a session that cannot be read is signed out, not thrown', () async {
      final AuthRepositoryImpl repo = AuthRepositoryImpl(_BrokenAuthDataSource());

      // Never throws: a user who cannot read their token must still reach the
      // login screen rather than a crash on launch.
      expect(await repo.restoreSession(), isNull);
    });

    test('signOut ends the session', () async {
      final AuthRepositoryImpl repo = AuthRepositoryImpl(
        FakeAuthDataSource(
          signedInAs: const AuthUser(id: 'usr_1', email: _email),
        ),
      );

      await repo.signOut();

      expect(await repo.restoreSession(), isNull);
    });
  });

  test('setPhone attaches the delivery number to the signed-in user', () async {
    final AuthRepositoryImpl repo = AuthRepositoryImpl(
      FakeAuthDataSource(signedInAs: const AuthUser(id: 'usr_1', email: _email)),
    );

    final AuthUser user = await repo.setPhone('+919876543210');

    expect(user.phone, '+919876543210');
    expect((await repo.restoreSession())?.phone, '+919876543210');
  });
}

/// A Keystore that fails outright — a corrupted keyset, or an OEM with a broken
/// provider.
class _BrokenAuthDataSource extends FakeAuthDataSource {
  @override
  AuthUser? currentUser() => throw Exception('keystore unavailable');
}
