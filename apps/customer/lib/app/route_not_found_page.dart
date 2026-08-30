import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// What a customer sees instead of GoRouter's developer error page (0151).
///
/// The screen it replaces prints the requested location, the route table and a
/// stack trace. That is the correct screen for whoever wrote the typo and a
/// frightening one for the person who received it — a food app that answers a
/// tap with a red stack trace reads as an app that has lost the order.
///
/// **It is not reachable today**, and the header on `errorBuilder` in
/// [routerProvider] says why: `initialLocation` is `/` and no route survives a
/// launch. What makes it worth a file is the path that has no test — a `route`
/// in a push payload naming a screen this build does not have. The server can
/// send that at any time, to a version of the app written before the screen
/// existed, and the customer who taps the notification is the one who finds out.
///
/// The location is shown deliberately. It is the one thing that makes a support
/// call answerable, and it is a path the customer's own device asked for rather
/// than anything private.
class RouteNotFoundPage extends StatelessWidget {
  const RouteNotFoundPage({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'We couldn\'t open that',
                style: t.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'The link you followed doesn\'t point anywhere in the app. '
                'Nothing has happened to your orders.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                location,
                style: t.bodySmall?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              // `go`, not `pop`. This can be the first and only route on the
              // stack — a cold start from a bad deep link has nothing behind it
              // to pop back to.
              ZopiqButton(
                label: 'Go to Home',
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
