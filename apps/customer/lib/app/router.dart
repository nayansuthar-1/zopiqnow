import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiqnow/app/app_shell.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/account_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/email_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_detail_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_success_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/orders_page.dart';
import 'package:zopiqnow/features/design_showcase/presentation/design_showcase_page.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_book_page.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_form_page.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/search/presentation/pages/search_page.dart';
import 'package:zopiqnow/app/coming_soon_page.dart';

/// Route name constants — referenced instead of raw path strings.
abstract final class Routes {
  static const String home = 'home';
  static const String showcase = 'showcase';
  static const String search = 'search';
  static const String menu = 'menu';
  static const String cart = 'cart';
  static const String checkout = 'checkout';
  static const String orderSuccess = 'orderSuccess';
  static const String orders = 'orders';
  static const String orderDetail = 'orderDetail';
  static const String addresses = 'addresses';
  static const String addressNew = 'addressNew';
  static const String addressEdit = 'addressEdit';
  static const String licenses = 'licenses';
  static const String account = 'account';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
}

/// Paths that require a signed-in user.
///
/// Browsing, searching, and *building a cart* stay open — that is how a food app
/// works, and demanding a phone number before a user has seen a menu is how you
/// lose them. Identity is required only where money and an address are.
///
/// `/orders` is here because an order history *is* identity: every receipt on it
/// carries the phone number the rider called and the address the food went to.
/// `/addresses` is here because an address book belongs to an account — there is
/// no such thing as a signed-out user's saved addresses.
const List<String> _protectedPrefixes = <String>[
  '/checkout',
  '/orders',
  '/addresses',
];

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

/// The root navigator's key — how code that isn't a widget reaches a
/// [BuildContext]. The mock payment gateway needs one to raise its sheet; the
/// real Razorpay SDK won't, and this can go with it.
final Provider<GlobalKey<NavigatorState>> rootNavigatorKeyProvider =
    Provider<GlobalKey<NavigatorState>>(
      (Ref ref) => GlobalKey<NavigatorState>(debugLabel: 'root'),
    );

/// The app's [GoRouter]. `redirect` is the single place auth affects navigation
/// (SAD 7.10) — no screen pushes a login route imperatively.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshListenable refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    navigatorKey: ref.watch(rootNavigatorKeyProvider),
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

          // Backing out of a sign-in must not land on the route that demanded
          // one — that would bounce straight back to this screen, forever. Home
          // is the only destination that is always safe.
          final String cancelTo = from != null && !_isProtected(from)
              ? from
              : '/';

          return EmailPage(
            onCancel: () => context.go(cancelTo),
            // Google signs in without a second screen, so nothing else rewrites
            // the stack. `go`, not `pop`: the login may have been *pushed* here
            // by the guard (Cart → "Proceed to checkout" pushes), and go_router
            // does not re-apply `redirect` to a pushed route — the sign-in would
            // move the location underneath a login screen that stays on top.
            // A `go` replaces the stack outright, which is the one thing that
            // reliably leaves this screen. `from` is the destination the guard
            // recorded; without it there is nowhere to be but Home.
            onSignedIn: () => context.go(from ?? '/'),
            // `go`, never `push`. A pushed route is imperative: it sits on the
            // navigator's stack *above* whatever location the router holds, and
            // no redirect can take it back down. Signing in would move the
            // router onward while the OTP screen stayed on top — spinning
            // forever, because it only ever stops spinning by being navigated
            // away from.
            onOtpSent: (String email) => context.goNamed(
              Routes.otp,
              queryParameters: <String, String>{'email': email, 'from': ?from},
            ),
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'otp',
            name: Routes.otp,
            builder: (BuildContext context, GoRouterState state) =>
                OtpPage(email: state.uri.queryParameters['email']!),
          ),
        ],
      ),

      // Tabbed shell. Each branch keeps its own stack and scroll position.
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          // Branch 0: Delivery (Home)
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                name: Routes.home,
                builder: (_, _) => const HomePage(),
              ),
            ],
          ),
          // Branch 1: Dining
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/dining',
                builder: (_, _) => const ComingSoonPage(title: 'Dining'),
              ),
            ],
          ),
          // Branch 2: Grocery
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/grocery',
                builder: (_, _) => const ComingSoonPage(title: 'Grocery'),
              ),
            ],
          ),
          // Branch 3: Cart
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

      // The address book. Guarded by prefix; the form nests under it so one
      // entry in _protectedPrefixes covers adding and editing too.
      GoRoute(
        path: '/addresses',
        name: Routes.addresses,
        builder: (_, _) => const AddressBookPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: Routes.addressNew,
            builder: (_, _) => const AddressFormPage(),
          ),
          GoRoute(
            path: ':id/edit',
            name: Routes.addressEdit,
            builder: (BuildContext context, GoRouterState state) {
              // The address rides along in `extra` — the list already holds it,
              // and re-fetching one row we have in hand would be a round trip
              // for nothing. A cold deep link has no `extra`, and rather than
              // silently turn an edit into an *add* (which would duplicate the
              // address), it lands on the book, where the row can be tapped.
              final Object? extra = state.extra;
              return extra is Address
                  ? AddressFormPage(existing: extra)
                  : const AddressBookPage();
            },
          ),
        ],
      ),

      // Order history. Guarded by prefix, like /checkout — and the detail route
      // nests under it for the same reason, so one entry in _protectedPrefixes
      // covers both.
      GoRoute(
        path: '/orders',
        name: Routes.orders,
        builder: (_, _) => const OrdersPage(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            name: Routes.orderDetail,
            builder: (BuildContext context, GoRouterState state) =>
                OrderDetailPage(orderId: state.pathParameters['id']!),
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
      GoRoute(
        path: '/account',
        name: Routes.account,
        builder: (_, _) => const AccountPage(),
      ),
      // Design-system reference screen — reachable via a debug entry on Home.
      GoRoute(
        path: '/showcase',
        name: Routes.showcase,
        builder: (_, _) => const DesignShowcasePage(),
      ),
      // Search is now outside the shell so it covers the bottom bar
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
  );
});

/// `/login?from=<encoded destination>`.
String _loginRedirect(String destination) => Uri(
  path: _loginPath,
  queryParameters: <String, String>{'from': destination},
).toString();
