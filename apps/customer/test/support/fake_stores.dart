import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/data/datasources/address_mock_datasource.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

import 'fake_auth_datasource.dart';

/// In-memory stand-ins for the two stores. Every widget test needs them: the
/// real ones are plugins, and a plugin in a widget test throws
/// `MissingPluginException`.
class FakeKeyValueStore implements KeyValueStore {
  FakeKeyValueStore([Map<String, String>? seed])
    : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

class FakeSecureStore implements SecureStore {
  FakeSecureStore([Map<String, String>? seed, this.latency = Duration.zero])
    : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  /// Models the Keystore round-trip. With [Duration.zero] a read resolves in a
  /// microtask, *before the first frame* — which would hide the splash that a
  /// real device always shows. Tests of the startup path pass a real delay.
  final Duration latency;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(latency);
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// An [AuthController] that starts from a known state instead of restoring a
/// session. Every other method — `verifyEmailOtp`, `setPhone`, `signOut` — still
/// runs for real against the overridden repository.
class ResolvedAuthController extends AuthController {
  ResolvedAuthController(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

/// Overrides every test that builds `ZopiqApp` needs: both stores in memory, an
/// in-memory auth transport, and auth already resolved.
///
/// Resolving auth up front matters: the real controller restores the session
/// asynchronously, so the first frame is the splash. Tests that assert on Home
/// would otherwise all need an extra `pump` for a startup path they are not
/// testing. Tests that *are* about auth omit [authState] and drive the real
/// restore themselves.
List<Override> storageOverrides({
  KeyValueStore? keyValueStore,
  SecureStore? secureStore,
  AuthDataSource? authDataSource,
  AddressDataSource? addressDataSource,
  AuthState? authState = const AuthSignedOut(),
}) => <Override>[
  keyValueStoreProvider.overrideWithValue(keyValueStore ?? FakeKeyValueStore()),
  secureStoreProvider.overrideWithValue(secureStore ?? FakeSecureStore()),
  authDataSourceProvider.overrideWithValue(
    authDataSource ?? FakeAuthDataSource(),
  ),
  // The address book is per-user and server-side now, so it is a network seam
  // like any other — and a widget test that reaches Supabase throws before it
  // reaches an assertion. The mock carries the Home/Work fixtures the repository
  // used to hand out to everybody.
  addressDataSourceProvider.overrideWithValue(
    addressDataSource ?? AddressMockDataSource(),
  ),
  if (authState != null)
    authControllerProvider.overrideWith(
      () => ResolvedAuthController(authState),
    ),
];
