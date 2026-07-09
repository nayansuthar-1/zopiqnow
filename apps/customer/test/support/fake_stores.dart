import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

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

/// An [AuthController] that starts from a known state instead of reading the
/// secure store. Every other method — `verifyOtp`, `signOut` — still runs for
/// real against the overridden repository.
class ResolvedAuthController extends AuthController {
  ResolvedAuthController(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

/// Overrides every test that builds `ZopiqApp` needs: both stores in memory, an
/// OTP data source with no artificial latency, and auth already resolved.
///
/// Resolving auth up front matters: the real controller restores the session
/// asynchronously, so the first frame is the splash. Tests that assert on Home
/// would otherwise all need an extra `pump` for a startup path they are not
/// testing. Tests that *are* about auth omit [authState] and drive the real
/// restore themselves.
List<Override> storageOverrides({
  KeyValueStore? keyValueStore,
  SecureStore? secureStore,
  AuthState? authState = const AuthSignedOut(),
}) => <Override>[
  keyValueStoreProvider.overrideWithValue(keyValueStore ?? FakeKeyValueStore()),
  secureStoreProvider.overrideWithValue(secureStore ?? FakeSecureStore()),
  authDataSourceProvider.overrideWithValue(
    AuthMockDataSource(latency: Duration.zero),
  ),
  if (authState != null)
    authControllerProvider.overrideWith(
      () => ResolvedAuthController(authState),
    ),
];
