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
    _challenge = _Challenge(to: email, issuedAt: DateTime.now());
  }

  @override
  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    _checkCode(sentTo: email, code: code);
    return _user = AuthUser(
      id: 'usr_${email.hashCode.toUnsigned(32)}',
      email: email,
    );
  }

  /// The SMS half, which the real transport routes through MSG91 and this one
  /// routes nowhere. Same challenge machinery as the email side because GoTrue
  /// enforces the same rules on both — one code at a time, a TTL, an attempt
  /// cap — and a fake that was stricter or laxer on one channel would test a
  /// product we do not ship.
  @override
  Future<void> sendPhoneOtp(String phone) async {
    sentTo.add(phone);
    _challenge = _Challenge(to: phone, issuedAt: DateTime.now());
  }

  @override
  Future<AuthUser> verifyPhoneOtp({
    required String phone,
    required String code,
  }) async {
    _checkCode(sentTo: phone, code: code);
    // Empty rather than invented: a phone-only GoTrue user genuinely has no
    // email, and `AuthUser.email` is not nullable. A fake that made one up
    // would hide the one case that behaves differently on the profile screen.
    return _user = AuthUser(
      id: 'usr_${phone.hashCode.toUnsigned(32)}',
      email: '',
      phone: phone,
    );
  }

  /// Spends one attempt against the standing challenge, or throws exactly what
  /// the real endpoint throws. Returns normally only when [code] is good.
  void _checkCode({required String sentTo, required String code}) {
    final _Challenge? challenge = _challenge;
    if (challenge == null || challenge.to != sentTo) {
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
  }

  /// Signs in as [googleUser] unless [googleCancels] is set, in which case it
  /// throws exactly what a dismissed account sheet throws.
  bool googleCancels = false;

  static const AuthUser googleUser = AuthUser(
    id: 'usr_google',
    email: 'google@example.com',
  );

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (googleCancels) throw const GoogleSignInCancelled();
    return _user = googleUser;
  }

  @override
  Future<AuthUser> saveProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    DateTime? dateOfBirth,
    Gender? gender,
  }) async {
    // Same merge rule as the real one: a field left out is left alone, which is
    // exactly what `copyWith`'s `?? this` does.
    return _user = _user!.copyWith(
      fullName: fullName,
      phone: phone,
      avatarUrl: avatarUrl,
      dateOfBirth: dateOfBirth,
      gender: gender,
    );
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _challenge = null;
  }

  /// Set to make the next [deleteAccount] refuse, the way the database refuses
  /// one — with a sentence written for the person reading it.
  String? deletionRefusal;

  @override
  Future<void> deleteAccount() async {
    final String? refusal = deletionRefusal;
    if (refusal != null) throw AccountDeletionRefused(refusal);
    _user = null;
    _challenge = null;
  }
}

class _Challenge {
  _Challenge({required this.to, required this.issuedAt});

  /// The address or number the code went to. Neutrally named because there is
  /// one challenge at a time and either channel may own it.
  final String to;
  final DateTime issuedAt;
  int attempts = 0;
}
