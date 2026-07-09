import 'dart:convert';

import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._dataSource, this._secureStore);

  final AuthMockDataSource _dataSource;
  final SecureStore _secureStore;

  /// One blob, one Keystore round-trip. Splitting the session across four keys
  /// would let a partial write leave a user half-signed-in.
  static const String _sessionKey = 'zopiq.auth.session';

  @override
  Future<AuthSession?> restoreSession() async {
    final String? raw = await _secureStore.read(_sessionKey);
    if (raw == null) return null;
    try {
      return _decode(raw);
    } on Object {
      // A session we cannot parse is a session we cannot use. Drop it and let
      // the user sign in again — never boot into a crash.
      await _secureStore.delete(_sessionKey);
      return null;
    }
  }

  @override
  Future<void> requestOtp(String phone) => _dataSource.requestOtp(phone);

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final AuthSession session = await _dataSource.verifyOtp(
      phone: phone,
      code: code,
    );
    await _secureStore.write(_sessionKey, _encode(session));
    return session;
  }

  @override
  Future<void> signOut() => _secureStore.delete(_sessionKey);

  static String _encode(AuthSession s) => jsonEncode(<String, String>{
    'userId': s.user.id,
    'phone': s.user.phone,
    'accessToken': s.tokens.accessToken,
    'refreshToken': s.tokens.refreshToken,
  });

  static AuthSession _decode(String raw) {
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    return AuthSession(
      user: AuthUser(
        id: json['userId']! as String,
        phone: json['phone']! as String,
      ),
      tokens: AuthTokens(
        accessToken: json['accessToken']! as String,
        refreshToken: json['refreshToken']! as String,
      ),
    );
  }
}
