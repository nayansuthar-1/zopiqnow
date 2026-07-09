import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

import '../../support/fake_stores.dart';

const String _phone = '+919876543210';

AuthRepositoryImpl _repo(FakeSecureStore store) =>
    AuthRepositoryImpl(AuthMockDataSource(latency: Duration.zero), store);

void main() {
  group('OTP verification', () {
    test('a correct code returns a session and persists it', () async {
      final FakeSecureStore store = FakeSecureStore();
      final AuthRepositoryImpl repo = _repo(store);

      await repo.requestOtp(_phone);
      final AuthSession session = await repo.verifyOtp(
        phone: _phone,
        code: AuthMockDataSource.devCode,
      );

      expect(session.user.phone, _phone);
      expect(session.tokens.accessToken, isNotEmpty);
      // Survives a restart: the next launch restores from the secure store.
      expect(await store.read('zopiq.auth.session'), isNotNull);
    });

    test('a wrong code throws InvalidOtp and persists nothing', () async {
      final FakeSecureStore store = FakeSecureStore();
      final AuthRepositoryImpl repo = _repo(store);

      await repo.requestOtp(_phone);

      expect(
        () => repo.verifyOtp(phone: _phone, code: '000000'),
        throwsA(isA<InvalidOtp>()),
      );
      expect(await store.read('zopiq.auth.session'), isNull);
    });

    test('the attempt cap trips TooManyOtpAttempts', () async {
      final AuthRepositoryImpl repo = _repo(FakeSecureStore());
      await repo.requestOtp(_phone);

      // The 5th wrong attempt is the one that trips the cap.
      for (int i = 0; i < AuthMockDataSource.maxAttempts - 1; i++) {
        await expectLater(
          repo.verifyOtp(phone: _phone, code: '000000'),
          throwsA(isA<InvalidOtp>()),
        );
      }
      await expectLater(
        repo.verifyOtp(phone: _phone, code: '000000'),
        throwsA(isA<TooManyOtpAttempts>()),
      );
      // Even the right code is refused once the challenge is locked out.
      await expectLater(
        repo.verifyOtp(phone: _phone, code: AuthMockDataSource.devCode),
        throwsA(isA<TooManyOtpAttempts>()),
      );
    });

    test('verifying without requesting a code throws OtpExpired', () async {
      final AuthRepositoryImpl repo = _repo(FakeSecureStore());
      await expectLater(
        repo.verifyOtp(phone: _phone, code: AuthMockDataSource.devCode),
        throwsA(isA<OtpExpired>()),
      );
    });

    test('a code issued for another number is refused', () async {
      final AuthRepositoryImpl repo = _repo(FakeSecureStore());
      await repo.requestOtp('+919000000000');
      await expectLater(
        repo.verifyOtp(phone: _phone, code: AuthMockDataSource.devCode),
        throwsA(isA<OtpExpired>()),
      );
    });
  });

  group('session persistence', () {
    test('restoreSession returns null when nothing is stored', () async {
      expect(await _repo(FakeSecureStore()).restoreSession(), isNull);
    });

    test('restoreSession round-trips the stored session', () async {
      final FakeSecureStore store = FakeSecureStore();
      final AuthRepositoryImpl repo = _repo(store);
      await repo.requestOtp(_phone);
      await repo.verifyOtp(phone: _phone, code: AuthMockDataSource.devCode);

      final AuthSession? restored = await _repo(store).restoreSession();
      expect(restored?.user.phone, _phone);
    });

    test('a corrupt session is discarded, not thrown', () async {
      final FakeSecureStore store = FakeSecureStore(<String, String>{
        'zopiq.auth.session': 'not json',
      });

      expect(await _repo(store).restoreSession(), isNull);
      // And it is cleared, so the next launch does not retry the same garbage.
      expect(await store.read('zopiq.auth.session'), isNull);
    });

    test('signOut clears the stored session', () async {
      final FakeSecureStore store = FakeSecureStore();
      final AuthRepositoryImpl repo = _repo(store);
      await repo.requestOtp(_phone);
      await repo.verifyOtp(phone: _phone, code: AuthMockDataSource.devCode);

      await repo.signOut();

      expect(await store.read('zopiq.auth.session'), isNull);
      expect(await repo.restoreSession(), isNull);
    });
  });

  test('displayPhone formats an Indian number for humans', () {
    const AuthUser user = AuthUser(id: 'u1', phone: _phone);
    expect(user.displayPhone, '98765 43210');
  });
}
