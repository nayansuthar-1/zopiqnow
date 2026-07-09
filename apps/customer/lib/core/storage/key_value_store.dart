import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret local state: the selected delivery address, recent searches.
///
/// **Never tokens.** Values here land in plain `SharedPreferences`, readable on
/// a rooted device. Anything sensitive belongs in the secure session store
/// (SAD 7.6 / 9.2).
///
/// Reads are synchronous so a provider can hydrate at first build without an
/// `AsyncValue` — the underlying prefs are loaded once, at startup.
abstract interface class KeyValueStore {
  String? getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesStore implements KeyValueStore {
  const SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
