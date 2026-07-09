import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/app/zopiq_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Phone-only portrait for now (Rule 1 — predictable on mid-range devices).
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  runApp(const ProviderScope(child: ZopiqApp()));
}
