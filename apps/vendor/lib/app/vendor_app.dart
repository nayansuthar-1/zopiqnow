import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';

/// The partner app.
///
/// Same design system as the customer app, deliberately: a vendor who has seen
/// the app their customers use should recognise this as the same company. What
/// is *not* shared is the information architecture — the customer app is a shop
/// and this is a worklist.
class VendorApp extends ConsumerWidget {
  const VendorApp({super.key});

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
