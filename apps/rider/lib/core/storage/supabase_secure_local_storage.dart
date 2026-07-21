import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/core/storage/secure_store.dart';

/// Where `supabase_flutter` keeps the rider's session.
///
/// Its default is `SharedPreferences` — a world-readable XML file on a rooted
/// device. The refresh token in there is a long-lived credential, and this one
/// opens a list of customers' home addresses and phone numbers, so it goes to
/// the Keystore instead.
///
/// A different key again from the customer and vendor apps'. On this app it
/// matters more than on either of them: one person can be a customer *and* a
/// rider on the same phone, and the two identities resolve to different rows in
/// different tables. A shared key would mean signing into one signs you out of
/// the other, at the exact moment somebody is standing in a stairwell with a
/// bag of food.
class SupabaseSecureLocalStorage extends LocalStorage {
  const SupabaseSecureLocalStorage(this._store);

  final SecureStore _store;

  static const String _key = 'zopiq.rider.supabase.session';

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
