import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';

/// Plain local state. Has no default: `SharedPreferences.getInstance()` is
/// async, so `main()` awaits it once and overrides this binding. Tests override
/// it with an in-memory fake, which is why nothing here touches a plugin.
final Provider<KeyValueStore> keyValueStoreProvider = Provider<KeyValueStore>(
  (Ref ref) => throw UnimplementedError(
    'keyValueStoreProvider must be overridden in main() or in a test.',
  ),
);

/// Secret local state. Unlike prefs this needs no async bootstrap, so it has a
/// real default — tests still override it to stay off the platform channel.
final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => const FlutterSecureStore(FlutterSecureStorage()),
);
