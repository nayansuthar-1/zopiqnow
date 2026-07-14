import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/core/storage/secure_store.dart';

/// Where `supabase_flutter` keeps the vendor's session.
///
/// Its default is `SharedPreferences` — a world-readable XML file on a rooted
/// device. The refresh token in there is a long-lived credential, and this one
/// opens a restaurant's order book, so it goes to the Keystore instead.
///
/// A different key from the customer app's, which costs nothing and means the
/// two sessions can never be confused if both apps are ever installed on the
/// same device — which, on a kitchen tablet that someone also orders lunch from,
/// they will be.
class SupabaseSecureLocalStorage extends LocalStorage {
  const SupabaseSecureLocalStorage(this._store);

  final SecureStore _store;

  static const String _key = 'zopiq.vendor.supabase.session';

  @override
  Future<void> initialize() async {}

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
