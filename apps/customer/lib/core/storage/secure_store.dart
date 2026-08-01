import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keystore-backed storage for secrets — today, the auth session (SAD 7.6).
///
/// Deals in opaque strings, not domain objects: serialisation belongs to the
/// feature that owns the secret, and `core` must not depend on `features`.
abstract interface class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [SecureStore] over `flutter_secure_storage`.
///
/// The default [AndroidOptions] are already the strong ones in 10.x — AES-GCM
/// data encryption with RSA-OAEP key wrapping in the Android Keystore, and no
/// legacy CBC/PKCS1 fallback. They require API 23+; our floor is 24 (Rule 1),
/// so there is nothing to version-guard here.
///
/// The iOS options are **not** left at their defaults, and the reason is the
/// one the Android manifest spells out beside `allowBackup="false"`. There, the
/// worry is Android auto-backup copying an encrypted session to the user's
/// Drive while the Keystore key that opens it stays on the old phone — a
/// restore that yields bytes nothing can read. The iOS Keychain has exactly the
/// same failure, arrived at differently: a default Keychain item is eligible
/// for iCloud Keychain sync and for an encrypted device backup, so the session
/// travels to a new phone where it is no longer valid.
///
/// `first_unlock_this_device` closes it from both ends. The `_this_device`
/// half is the direct counterpart of `allowBackup="false"` — the item is never
/// synced and never restored onto different hardware. The `first_unlock` half
/// is what keeps it readable after a reboot before the user has unlocked,
/// which a push arriving on a locked phone needs; the stricter `unlocked`
/// variants would make the session unreadable in exactly that case.
class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static const IOSOptions _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key, iOptions: _ios);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value, iOptions: _ios);

  @override
  Future<void> delete(String key) => _storage.delete(key: key, iOptions: _ios);
}
