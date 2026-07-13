import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/app/env.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/core/storage/supabase_secure_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phone-only portrait for now (Rule 1 — predictable on mid-range devices).
  // Awaited now that `main` is async: `unawaited_futures` is a lint here.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // The only blocking startup work (Rule 1.4). Reads afterwards are synchronous,
  // so Home paints its saved address on the first frame rather than flashing
  // "Set delivery location" and then correcting itself.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // One instance, two consumers: Supabase persists the session through it, and
  // the rest of the app reads secrets through the provider below.
  const SecureStore secureStore = FlutterSecureStore(FlutterSecureStorage());

  // Sets up the Postgres client (and, later, the realtime socket for order
  // tracking). It does not open a connection here — the first query does.
  //
  // It *does* restore the auth session, out of the Keystore, before `runApp`.
  // That is what lets `AuthController` answer "signed in?" without a round trip
  // and the router's redirect without an await.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SupabaseSecureLocalStorage(secureStore),
    ),
  );

  runApp(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(SharedPreferencesStore(prefs)),
        secureStoreProvider.overrideWithValue(secureStore),
      ],
      child: const ZopiqApp(),
    ),
  );
}
