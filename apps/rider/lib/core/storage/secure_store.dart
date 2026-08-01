import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keystore-backed storage for secrets — here, the rider's session.
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
/// data encryption with RSA-OAEP key wrapping in the Android Keystore. They
/// require API 23+; our floor is 24, so there is nothing to version-guard.
///
/// The iOS options are deliberately not the defaults: a default Keychain item
/// syncs to iCloud Keychain and rides along in a device backup, so this rider's
/// session — which opens a list of customers' addresses and phone numbers —
/// would travel to another phone. `_this_device` is the counterpart of the
/// manifest's `allowBackup="false"`; `first_unlock` keeps it readable after a
/// reboot, which a job push arriving on a locked phone needs. See the customer
/// app's copy for the longer note.
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

/// The same store `main` hands to Supabase, for the parts of the app that reach
/// it through Riverpod rather than through a constructor.
///
/// `FlutterSecureStorage` is a handle over a platform channel, not a connection,
/// so a second instance is not a second anything — it opens the same Keystore
/// entry the first one does.
final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => const FlutterSecureStore(FlutterSecureStorage()),
);
