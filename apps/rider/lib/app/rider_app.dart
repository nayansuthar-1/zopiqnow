import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/app/router.dart';

/// The delivery-partner app.
///
/// Same design system as the other two, deliberately. What is not shared is the
/// information architecture: the customer app is a shop, the vendor app is a
/// worklist, and this is a single instruction — collect this, take it there.
class RiderApp extends ConsumerWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      // Was 'Zopiqnow Partner' — the vendor app's title, copied along with the
      // rest of this file. It is what Android shows in the task switcher, and a
      // rider holding both apps saw two identically named cards.
      title: 'Zopiq Rider',
      debugShowCheckedModeBanner: false,
      theme: ZopiqTheme.light,
      darkTheme: ZopiqTheme.dark,
      // Pinned for the reason the vendor app pins it: `ThemeMode.system` would
      // hand a rider on a dark-mode phone a theme this app has never been
      // reviewed in, outdoors, one-handed.
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
