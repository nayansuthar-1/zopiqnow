import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/app/providers/splash_gate_provider.dart';
import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_datasource.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_mock_datasource.dart';
import 'package:zopiqnow/features/favourites/presentation/providers/favourites_providers.dart';
import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/data/datasources/address_mock_datasource.dart';
import 'package:zopiqnow/features/location/presentation/pages/location_gate_page.dart';
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
/// [locationGateAnswered] is what keeps a test about the *cart* from being a
/// test about the location gate. The router sends `/` to the gate whenever no
/// address has been chosen this run, so without this every case that pumps the
/// app asserts against `LocationGatePage` and finds no Home, no tabs and no
/// cart pill. Answering it is the honest fake: the gate is in-memory and
/// per-run by design, so "already answered" is a state the real app reaches a
/// second after launch. Tests that *are* about the gate pass `false` and drive
/// it themselves.
List<Override> storageOverrides({
  KeyValueStore? keyValueStore,
  SecureStore? secureStore,
  AuthDataSource? authDataSource,
  AddressDataSource? addressDataSource,
  FavouritesDataSource? favouritesDataSource,
  AuthState? authState = const AuthSignedOut(),
  bool locationGateAnswered = true,
}) => <Override>[
  keyValueStoreProvider.overrideWithValue(keyValueStore ?? FakeKeyValueStore()),
  secureStoreProvider.overrideWithValue(secureStore ?? FakeSecureStore()),
  // The splash holds itself open for the length of its animation in the real
  // app. That is brand, not behaviour, and a suite that waited it out on every
  // cold start would pay for it on each case — so here the gate is open from
  // the first frame and the splash lasts exactly as long as the session read,
  // which is the thing these tests are actually about.
  splashHoldProvider.overrideWithValue(Duration.zero),
  locationGateProvider.overrideWith((Ref _) => locationGateAnswered),
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
  // Every restaurant card carries a heart, so *every* widget test that renders
  // the feed reads favourites — and a widget test that reaches Supabase throws
  // before it reaches an assertion.
  favouritesDataSourceProvider.overrideWithValue(
    favouritesDataSource ?? FavouritesMockDataSource(),
  ),
  if (authState != null)
    authControllerProvider.overrideWith(
      () => ResolvedAuthController(authState),
    ),
];
