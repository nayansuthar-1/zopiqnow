import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/core/storage/secure_store.dart';

/// Where `supabase_flutter` keeps the session.
///
/// Its default is `SharedPreferences` — a world-readable XML file on a rooted
/// device. The refresh token in there is a long-lived credential, so it goes to
/// the Keystore instead (SAD 7.6), which is where this app has always kept it.
class SupabaseSecureLocalStorage extends LocalStorage {
  const SupabaseSecureLocalStorage(this._store);

  final SecureStore _store;

  static const String _key = 'zopiq.supabase.session';

  /// The pre-Supabase session blob. A different shape under a different key, so
  /// it is dead weight in the Keystore the moment this build runs.
  static const String _legacyKey = 'zopiq.auth.session';

  @override
  Future<void> initialize() => _store.delete(_legacyKey);

  @override
  Future<bool> hasAccessToken() async => await _store.read(_key) != null;

  @override
  Future<String?> accessToken() => _store.read(_key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_key, persistSessionString);

  @override
  Future<void> removePersistedSession() => _store.delete(_key);
}
