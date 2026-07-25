import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/notifications/push_service.dart';

/// Root of the zopiqnow customer app. Wires the design-system themes
/// (light + dark) and the go_router instance from Riverpod.
///
/// Stateful for one reason: a notification tap has to become a route. The tap
/// arrives at [PushService] — which runs before `runApp` and has no router — so
/// it parks an order id and this drains it. A tap that woke the app from dead
/// therefore still lands on the tracking screen, one frame after it opens.
class ZopiqApp extends ConsumerStatefulWidget {
  const ZopiqApp({super.key});

  @override
  ConsumerState<ZopiqApp> createState() => _ZopiqAppState();
}

class _ZopiqAppState extends ConsumerState<ZopiqApp> {
  @override
  void initState() {
    super.initState();
    PushService.pendingOrderId.addListener(_openPendingOrder);
    // A cold start's tap is already waiting; the listener would never fire for
    // it. Deferred to after the first frame so there is a router to navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingOrder());
  }

  @override
  void dispose() {
    PushService.pendingOrderId.removeListener(_openPendingOrder);
    super.dispose();
  }

  void _openPendingOrder() {
    final String? orderId = PushService.pendingOrderId.value;
    if (orderId == null || !mounted) return;
    // Cleared first: the navigation may itself be redirected to sign-in, and a
    // pending id left behind would reopen the order on every rebuild.
    PushService.pendingOrderId.value = null;
    ref.read(routerProvider).go('/orders/$orderId');
  }

  @override
  Widget build(BuildContext context) {
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
