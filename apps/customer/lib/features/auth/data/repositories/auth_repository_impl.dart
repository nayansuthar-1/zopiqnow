import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/domain/repositories/auth_repository.dart';

/// There is no persistence code here any more: Supabase's client restores and
/// refreshes the session itself, out of the Keystore (see
/// `SupabaseSecureLocalStorage`). Keeping a second copy of the tokens is how you
/// end up serving a stale one after a refresh.
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._dataSource);

  final AuthDataSource _dataSource;

  @override
  Future<AuthUser?> restoreSession() async {
    try {
      return _dataSource.currentUser();
    } on Object {
      // A session Supabase cannot read is a session we cannot use. Signed out is
      // recoverable; a crash on launch is not.
      return null;
    }
  }

  @override
  Future<void> sendEmailOtp(String email) => _dataSource.sendEmailOtp(email);

  @override
  Future<AuthUser> verifyEmailOtp({
    required String email,
    required String code,
  }) => _dataSource.verifyEmailOtp(email: email, code: code);

  @override
  Future<AuthUser> setPhone(String phone) => _dataSource.setPhone(phone);

  @override
  Future<void> signOut() => _dataSource.signOut();
}
