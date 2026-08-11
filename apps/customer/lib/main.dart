import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/supabase_bootstrap.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/core/observability/crash_reporter.dart';
import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/secure_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
import 'package:zopiqnow/features/notifications/push_service.dart';

/// Everything above `runApp` is time the customer spends looking at a flat
/// orange window with nothing on it, because until the first frame there is no
/// Flutter to draw the splash. So the rule for this function is: get to
/// `runApp`, then do the work.
///
/// Measured on a CPH2263, first launch after install — the worst case, and the
/// one that made this necessary. Before: 6.2s to the first frame, of which 1.2s
/// was an awaited orientation call and 3.4s was `Supabase.initialize`. After:
/// both moved off the path, and the brand animation covers them instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First, before anything can throw. It costs nothing and it is the difference
  // between a startup failure that is reported and one that is simply a customer
  // staring at a dead splash screen. Firebase is not up yet — see the class for
  // what happens to errors raised in that window.
  CrashReporter.attach();

  // Phone-only portrait for now (Rule 1 — predictable on mid-range devices).
  //
  // Deliberately not awaited: the round trip cost 1.2s on a cold first launch,
  // all of it in front of the first frame, and nothing about the frame depends
  // on the answer — the app is portrait in its manifest and the engine has no
  // rotation to apply by the time this lands. `unawaited` rather than a bare
  // call because `unawaited_futures` is a lint here.
  unawaited(
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]),
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // The only blocking startup work (Rule 1.4) — and it stays blocking because it
  // is 1-5ms and because the alternative is plumbing an async binding through
  // every provider that reads it. Reads afterwards are synchronous, so Home
  // paints its saved address on the first frame rather than flashing "Set
  // delivery location" and then correcting itself.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // One instance, two consumers: Supabase persists the session through it, and
  // the rest of the app reads secrets through the provider below.
  const SecureStore secureStore = FlutterSecureStore(FlutterSecureStorage());

  // Started here, awaited below. See [SupabaseBootstrap] for why the ordering
  // around `runApp` is the whole point, and [AuthController] for who waits.
  final Future<void> supabaseReady = SupabaseBootstrap.start(secureStore);

  runApp(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(SharedPreferencesStore(prefs)),
        secureStoreProvider.overrideWithValue(secureStore),
      ],
      child: const ZopiqApp(),
    ),
  );

  // The splash is on screen from here down.
  //
  // Nothing below may touch `Supabase.instance` before this resolves, and
  // everything below does: push registers a token against the restored session.
  await supabaseReady;

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
