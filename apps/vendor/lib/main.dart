import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/app/env.dart';
import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/core/storage/secure_store.dart';
import 'package:zopiq_vendor/core/storage/supabase_secure_local_storage.dart';
import 'package:zopiq_vendor/features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-locked, like the customer app. A tablet in a stand is the obvious
  // next form factor, and landscape will have to be earned properly — a queue
  // that reflows into two columns is a design decision, not a rotation.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  const SecureStore secureStore = FlutterSecureStore(FlutterSecureStorage());

  // Restores the session out of the Keystore before `runApp`, which is what lets
  // the router answer "is this kitchen signed in?" without a round trip.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SupabaseSecureLocalStorage(secureStore),
    ),
  );

  runApp(const ProviderScope(child: VendorApp()));

  // After the first frame, not before: push brings up Firebase and asks the
  // notification permission, and that prompt should land over a running app, not
  // a blank screen. Guarded internally — if any of it fails, the app is unharmed.
  await PushService.start();
}
