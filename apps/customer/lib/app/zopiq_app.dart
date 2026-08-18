import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/consent_recorder.dart';
import 'package:zopiqnow/app/providers/locale_provider.dart';
import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/core/l10n/strings.dart';
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
    final AppStrings strings = ref.watch(appStringsProvider);

    // Watched, not read: a Provider is created lazily and one that nobody
    // watches never runs, so its `ref.listen` on the auth state would never be
    // registered and the acceptance would never be written. Here because this
    // is the one widget that outlives every route — the sign-in screen it
    // belongs to is gone by the time the sign-in it is recording completes.
    ref.watch(consentRecorderProvider);

    return MaterialApp.router(
      title: 'zopiqnow',
      debugShowCheckedModeBanner: false,
      theme: ZopiqTheme.light,
      darkTheme: ZopiqTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // The string table goes in through `builder` rather than by wrapping
      // `MaterialApp` itself, because this is the one place that is *inside*
      // the app and still above every routed screen. Wrapping from outside
      // would put it above the Navigator, where the routes could not see it.
      //
      // **`locale:` is deliberately not set.** Without `flutter_localizations`
      // — the dependency this whole approach exists to avoid — Flutter has no
      // Material delegates for `hi`, so naming the locale would either assert
      // or silently resolve back to English while doing nothing for our own
      // copy. Our strings switch on the provider above; Flutter's own built-in
      // widget text (the text-selection menu, date pickers) stays English.
      // That is the accepted cost of the zero-dependency route.
      builder: (BuildContext context, Widget? child) => AppStringsScope(
        strings: strings,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
