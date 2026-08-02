import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/app/env.dart';
import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/core/storage/secure_store.dart';
import 'package:zopiq_rider/core/storage/supabase_secure_local_storage.dart';
import 'package:zopiq_rider/features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-locked. This app is used one-handed, at a counter or on a doorstep.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  const SecureStore secureStore = FlutterSecureStore(FlutterSecureStorage());

  // Restores the session out of the Keystore before `runApp`, which is what lets
  // the router answer "is this rider signed in?" without a round trip.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SupabaseSecureLocalStorage(secureStore),
    ),
  );

  runApp(const ProviderScope(child: RiderApp()));

  // After the first frame, not before — the vendor app has always done it this
  // way and this one had not. `PushService.start()` brings up Firebase, asks the
  // notification permission and registers a token against the restored session:
  // three round trips, all of them on the critical path to first paint while it
  // was awaited above. A rider opening the app at the start of a shift was
  // looking at a blank screen for the duration. It still runs after Supabase is
  // up, which is the only ordering that actually matters, and it is still
  // guarded internally — no Firebase config means a no-op and the app runs on.
  await PushService.start();
}
