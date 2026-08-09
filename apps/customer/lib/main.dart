import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/env.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/core/observability/crash_reporter.dart';
import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/core/storage/supabase_secure_local_storage.dart';
import 'package:zopiqnow/features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First, before anything can throw. It costs nothing and it is the difference
  // between a startup failure that is reported and one that is simply a customer
  // staring at a dead splash screen. Firebase is not up yet — see the class for
  // what happens to errors raised in that window.
  CrashReporter.attach();

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

  // After the first frame, not before. Bringing up Firebase, asking the
  // notification permission and registering a token are three round trips, and
  // awaiting them above put all three between the splash and the first paint —
  // on a mid-range phone on a slow connection, seconds of nothing. It still runs
  // after Supabase is up, which is the ordering that matters (the token
  // registers against the restored session), and the permission prompt now
  // lands over a running app rather than a blank screen, which is where a
  // prompt should land. Guarded internally: no Firebase config means a no-op.
  //
  // Crash reporting goes up first, and separately, so that it does not inherit
  // push's failure modes: a denied notification permission must not cost us the
  // report of the exception thrown a second later. Both bring Firebase up; the
  // call is idempotent and whichever arrives first wins.
  await CrashReporter.enable();
  await PushService.start();

  // Last, and behind a painted screen: the image cache is what makes a cold
  // launch draw the catalogue without downloading it again, and this is the one
  // thing that keeps it from growing without a ceiling. It never throws.
  await ZopiqImageStore.instance.sweep();
}
