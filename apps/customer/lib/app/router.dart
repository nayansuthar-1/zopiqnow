import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiqnow/app/app_shell.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/phone_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_success_page.dart';
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
  static const String checkout = 'checkout';
  static const String orderSuccess = 'orderSuccess';
  static const String licenses = 'licenses';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
}

/// Paths that require a signed-in user.
///
/// Browsing, searching, and *building a cart* stay open — that is how a food app
/// works, and demanding a phone number before a user has seen a menu is how you
/// lose them. Identity is required only where money and an address are.
const List<String> _protectedPrefixes = <String>['/checkout'];

const String _splashPath = '/splash';
const String _loginPath = '/login';

bool _isProtected(String location) =>
    _protectedPrefixes.any((String p) => location.startsWith(p));

/// Bridges Riverpod's [authControllerProvider] to the [Listenable] GoRouter
/// wants. Without it, signing in changes state but never re-runs `redirect`.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<AuthState>(
      authControllerProvider,
      (AuthState? _, AuthState _) => notifyListeners(),
    );
  }
}

/// The app's [GoRouter]. `redirect` is the single place auth affects navigation
/// (SAD 7.10) — no screen pushes a login route imperatively.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshListenable refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authControllerProvider);
      final String location = state.matchedLocation;

      // 1. Session still being read from the Keystore. Park on the splash and
      //    remember where we were going — a cold deep link to a protected route
      //    must survive the restore, not be thrown away.
      if (auth is AuthUnknown) {
        if (location == _splashPath) return null;
        return Uri(
          path: _splashPath,
          queryParameters: <String, String>{'from': state.uri.toString()},
        ).toString();
      }

      // 2. Restore finished. Leave the splash for wherever we were headed,
      //    re-applying the guard to that destination.
      if (location == _splashPath) {
        final String target = state.uri.queryParameters['from'] ?? '/';
        if (auth is AuthSignedOut && _isProtected(target)) {
          return _loginRedirect(target);
        }
        return target;
      }

      final bool onAuthRoute = location.startsWith(_loginPath);

      // 3. Signing in is what sends the user onward — the OTP screen never
      //    navigates itself. `from` carries the originally requested route.
      if (auth is AuthSignedIn && onAuthRoute) {
        return state.uri.queryParameters['from'] ?? '/';
      }

      // 4. The guard proper.
      if (auth is AuthSignedOut && _isProtected(location)) {
        return _loginRedirect(state.uri.toString());
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: _splashPath,
        name: Routes.splash,
        builder: (_, _) => const SplashPage(),
      ),
      GoRoute(
        path: _loginPath,
        name: Routes.login,
        builder: (BuildContext context, GoRouterState state) {
          // `from` rides along to the OTP screen: the redirect reads it there,
          // after sign-in, to resume the originally requested route.
          final String? from = state.uri.queryParameters['from'];
          return PhonePage(
            onOtpSent: (String phone) => context.pushNamed(
              Routes.otp,
              queryParameters: <String, String>{'phone': phone, 'from': ?from},
            ),
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'otp',
            name: Routes.otp,
            builder: (BuildContext context, GoRouterState state) =>
                OtpPage(phone: state.uri.queryParameters['phone']!),
          ),
        ],
      ),

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
                builder: (BuildContext context, _) => CartPage(
                  onBrowse: () => context.goNamed(Routes.home),
                  onCheckout: () => context.pushNamed(Routes.checkout),
                ),
              ),
            ],
          ),
        ],
      ),

      // Outside the shell: identity, address, coupon, and payment. The success
      // page nests under /checkout so the auth guard covers it by prefix.
      GoRoute(
        path: '/checkout',
        name: Routes.checkout,
        builder: (_, _) => const CheckoutPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'success',
            name: Routes.orderSuccess,
            builder: (_, _) => const OrderSuccessPage(),
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

/// `/login?from=<encoded destination>`.
String _loginRedirect(String destination) => Uri(
  path: _loginPath,
  queryParameters: <String, String>{'from': destination},
).toString();
