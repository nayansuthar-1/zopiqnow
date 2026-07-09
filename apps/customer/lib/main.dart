import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';

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

  runApp(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(SharedPreferencesStore(prefs)),
      ],
      child: const ZopiqApp(),
    ),
  );
}
