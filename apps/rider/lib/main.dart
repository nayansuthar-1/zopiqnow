import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zopiq_map/zopiq_map.dart';

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

  // Wire push after Supabase is up so a token can register against the restored
  // session. Guarded internally: no Firebase config means a no-op, app runs on.
  await PushService.start();

  // Installs the headers every Ola tile request carries. A static on MapLibre's
  // platform channel, so it is set once here rather than per map. A missing key
  // is a no-op and the job map says so on its own face.
  await OlaMaps.configure(Env.olaMapsApiKey);

  runApp(const ProviderScope(child: RiderApp()));
}
