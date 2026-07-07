import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
import 'package:zopiqnow/app/router.dart';

/// Root of the zopiqnow customer app. Wires the design-system themes
/// (light + dark) and the go_router instance from Riverpod.
class ZopiqApp extends ConsumerWidget {
  const ZopiqApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'zopiqnow',
      debugShowCheckedModeBanner: false,
      theme: ZopiqTheme.light,
      darkTheme: ZopiqTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
