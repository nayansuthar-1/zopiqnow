import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiqnow/app/app_shell.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/design_showcase/presentation/design_showcase_page.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/search/presentation/pages/search_page.dart';

/// Route name constants — referenced instead of raw path strings.
abstract final class Routes {
  static const String home = 'home';
  static const String showcase = 'showcase';
  static const String search = 'search';
  static const String menu = 'menu';
  static const String cart = 'cart';
  static const String licenses = 'licenses';
}

/// The app's [GoRouter], exposed through Riverpod so guards/redirects can later
/// react to auth and other providers (SAD 7.10).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      // Tabbed shell. Each branch keeps its own stack and scroll position.
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                name: Routes.home,
                builder: (_, _) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                name: Routes.search,
                builder: (BuildContext context, _) => SearchPage(
                  onOpenRestaurant: (Restaurant r) => context.pushNamed(
                    Routes.menu,
                    pathParameters: <String, String>{'id': r.id},
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/cart',
                name: Routes.cart,
                builder: (BuildContext context, _) =>
                    CartPage(onBrowse: () => context.goNamed(Routes.home)),
              ),
            ],
          ),
        ],
      ),

      // Outside the shell, so it covers the bottom bar: the menu docks its own
      // CartBar, and stacking the two would put a bar on top of a bar.
      //
      // Path-based, not `extra`-based: a cold deep link to a restaurant must
      // resolve from the id alone, with no Home feed in memory.
      GoRoute(
        path: '/restaurant/:id',
        name: Routes.menu,
        builder: (BuildContext context, GoRouterState state) => MenuPage(
          restaurantId: state.pathParameters['id']!,
          onViewCart: () => context.goNamed(Routes.cart),
        ),
      ),
      GoRoute(
        path: '/licenses',
        name: Routes.licenses,
        builder: (_, _) => const LicensesPage(),
      ),
      // Design-system reference screen — reachable via a debug entry on Home.
      GoRoute(
        path: '/showcase',
        name: Routes.showcase,
        builder: (_, _) => const DesignShowcasePage(),
      ),
    ],
  );
});
