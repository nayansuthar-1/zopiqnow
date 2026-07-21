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
      title: 'Zopiqnow Partner',
      debugShowCheckedModeBanner: false,
      theme: ZopiqTheme.light,
      darkTheme: ZopiqTheme.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
