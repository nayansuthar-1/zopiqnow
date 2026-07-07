import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiqnow/features/design_showcase/presentation/design_showcase_page.dart';

/// Route name constants — referenced instead of raw path strings.
abstract final class Routes {
  static const String showcase = 'showcase';
}

/// The app's [GoRouter], exposed through Riverpod so guards/redirects can later
/// react to auth and other providers (SAD 7.10).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: Routes.showcase,
        builder: (_, _) => const DesignShowcasePage(),
      ),
    ],
  );
});
