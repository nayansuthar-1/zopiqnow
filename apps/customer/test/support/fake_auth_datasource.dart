import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// Supabase Auth, in memory.
///
/// Faithful to the rules the real endpoint enforces — a 6-digit code, a TTL, an
/// attempt cap — so the screens are tested against the failures they will
/// actually meet, not just the happy path.
class FakeAuthDataSource implements AuthDataSource {
  FakeAuthDataSource({AuthUser? signedInAs}) : _user = signedInAs;

  /// The code every fake challenge accepts. There is no inbox to read in a test.
  static const String devCode = '123456';

  static const Duration ttl = Duration(minutes: 5);
  static const int maxAttempts = 5;

  AuthUser? _user;
  _Challenge? _challenge;

  /// Sends nowhere. Recorded so a test can assert what was asked for.
  final List<String> sentTo = <String>[];

  @override
  AuthUser? currentUser() => _user;

  @override
  Future<void> sendEmailOtp(String email) async {
    sentTo.add(email);
    _challenge = _Challenge(email: email, issuedAt: DateTime.now());
  }

  @override
  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final _Challenge? challenge = _challenge;
    if (challenge == null || challenge.email != email) {
      throw const OtpExpired();
    }
    if (DateTime.now().difference(challenge.issuedAt) > ttl) {
      _challenge = null;
      throw const OtpExpired();
    }
    if (challenge.attempts >= maxAttempts) throw const TooManyOtpAttempts();

    challenge.attempts++;
    if (code != devCode) {
      if (challenge.attempts >= maxAttempts) throw const TooManyOtpAttempts();
      throw const InvalidOtp();
    }

    _challenge = null;
    return _user = AuthUser(
      id: 'usr_${email.hashCode.toUnsigned(32)}',
      email: email,
    );
  }

  @override
  Future<AuthUser> setPhone(String phone) async =>
      _user = _user!.copyWith(phone: phone);

  @override
  Future<void> signOut() async {
    _user = null;
    _challenge = null;
  }
}

class _Challenge {
  _Challenge({required this.email, required this.issuedAt});

  final String email;
  final DateTime issuedAt;
  int attempts = 0;
}
