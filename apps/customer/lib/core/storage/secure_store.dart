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
class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
