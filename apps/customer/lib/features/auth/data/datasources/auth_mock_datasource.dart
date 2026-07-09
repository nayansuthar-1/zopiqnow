import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// In-memory stand-in for `auth-service` (SAD 9.3), kept faithful to the
/// contract the real endpoint will enforce: 6-digit code, 5-minute TTL, and a
/// 5-attempt cap per challenge.
///
/// Modelling those rules now — rather than accepting any code — means the OTP
/// screen already has an expired state and a lockout state to render, and Step 7
/// swaps the transport without discovering new failure modes.
class AuthMockDataSource {
  AuthMockDataSource({this.latency = const Duration(milliseconds: 600)});

  final Duration latency;

  /// The code every mock challenge accepts. There is no SMS to read, so a fixed
  /// value is the only way in; the OTP screen surfaces it in debug builds.
  static const String devCode = '123456';

  static const Duration ttl = Duration(minutes: 5);
  static const int maxAttempts = 5;

  _Challenge? _challenge;

  Future<void> requestOtp(String phone) async {
    await Future<void>.delayed(latency);
    _challenge = _Challenge(phone: phone, issuedAt: DateTime.now());
  }

  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
  }) async {
    await Future<void>.delayed(latency);

    final _Challenge? challenge = _challenge;
    if (challenge == null || challenge.phone != phone) {
      throw const OtpExpired();
    }
    if (DateTime.now().difference(challenge.issuedAt) > ttl) {
      _challenge = null;
      throw const OtpExpired();
    }
    if (challenge.attempts >= maxAttempts) {
      throw const TooManyOtpAttempts();
    }

    challenge.attempts++;
    if (code != devCode) {
      if (challenge.attempts >= maxAttempts) throw const TooManyOtpAttempts();
      throw const InvalidOtp();
    }

    _challenge = null;
    return AuthSession(
      user: AuthUser(id: 'usr_${phone.hashCode.toUnsigned(32)}', phone: phone),
      // Shaped like the real thing (SAD 9.2) so nothing downstream is surprised
      // when a genuine RS256 JWT shows up here.
      tokens: AuthTokens(
        accessToken: 'mock.access.${DateTime.now().millisecondsSinceEpoch}',
        refreshToken: 'mock.refresh.${phone.hashCode.toUnsigned(32)}',
      ),
    );
  }
}

class _Challenge {
  _Challenge({required this.phone, required this.issuedAt});

  final String phone;
  final DateTime issuedAt;
  int attempts = 0;
}
