import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiqnow/app/app_shell.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/account_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/delete_account_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/legal_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/profile_details_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/email_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/invoice_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_detail_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_success_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/orders_page.dart';
import 'package:zopiqnow/features/design_showcase/presentation/design_showcase_page.dart';
import 'package:zopiqnow/features/favourites/presentation/pages/favourites_page.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_bag_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_checkout_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_order_detail_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_orders_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_placed_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_shop_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gifts_page.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_book_page.dart';
import 'package:zopiqnow/features/location/presentation/pages/address_form_page.dart';
import 'package:zopiqnow/features/location/presentation/pages/location_gate_page.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/notifications/presentation/pages/notifications_page.dart';
import 'package:zopiqnow/features/search/presentation/pages/search_page.dart';
import 'package:zopiqnow/app/coming_soon_page.dart';

/// Route name constants — referenced instead of raw path strings.
abstract final class Routes {
  static const String home = 'home';
  static const String showcase = 'showcase';
  static const String search = 'search';
  static const String menu = 'menu';
  static const String gifts = 'gifts';
  static const String giftShop = 'giftShop';
  static const String giftBag = 'giftBag';
  static const String giftCheckout = 'giftCheckout';
  static const String giftPlaced = 'giftPlaced';
  static const String giftOrders = 'giftOrders';
  static const String giftOrderDetail = 'giftOrderDetail';
  static const String cart = 'cart';
  static const String checkout = 'checkout';
  static const String orderSuccess = 'orderSuccess';
  static const String orders = 'orders';
  static const String orderDetail = 'orderDetail';
  static const String invoice = 'invoice';
  static const String favourites = 'favourites';
  static const String addresses = 'addresses';
  static const String addressNew = 'addressNew';
  static const String addressEdit = 'addressEdit';
  static const String licenses = 'licenses';
  static const String account = 'account';
  static const String profile = 'profile';
  static const String deleteAccount = 'deleteAccount';
  static const String legal = 'legal';
  static const String notifications = 'notifications';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String locationGate = 'locationGate';
}

/// Paths that require a signed-in user.
///
/// Browsing, searching, and *building a cart* stay open — that is how a food app
/// works, and demanding a phone number before a user has seen a menu is how you
/// lose them. Identity is required only where money and an address are.
///
/// `/orders` is here because an order history *is* identity: every receipt on it
/// carries the phone number the rider called and the address the food went to.
/// `/addresses` and `/favourites` are here because both belong to an account —
/// there is no such thing as a signed-out user's saved addresses, or their saved
/// restaurants.
const List<String> _protectedPrefixes = <String>[
  '/checkout',
  '/orders',
  '/addresses',
  '/favourites',
  // Gifts browse open, like food — the catalogue is the shop window. Identity
  // is required at exactly the same two places it is for food: where money and
  // an address are, and where a receipt with somebody's address on it is read.
  // `/gift-bag` is deliberately *not* here: building a bag is browsing.
  '/gift-checkout',
  '/gift-orders',
];

const String _splashPath = '/splash';
const String _loginPath = '/login';
const String _locationGatePath = '/welcome/location';

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

      // 5. Where are we delivering? Asked once a run, and **only on the way to
      //    Home** — that is what makes this "at the start of the app" rather
      //    than a toll booth on every navigation. A push notification opening
      //    an order, a deep link to a restaurant, and the trip back from the
      //    address book all pass straight through; none of them is a customer
      //    arriving at a screen whose every number depends on an address they
      //    have not given.
      //
      //    After the auth guard deliberately: a protected deep link should reach
      //    sign-in first, because that is the thing actually stopping it.
      if (location == '/' &&
          !ref.read(locationGateProvider) &&
          ref.read(selectedAddressProvider) == null) {
        return _locationGatePath;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: _splashPath,
        name: Routes.splash,
        builder: (_, _) => const SplashPage(),
      ),
      // Outside the shell: the bottom pills would offer four tabs the customer
      // cannot usefully reach yet.
      GoRoute(
        path: _locationGatePath,
        name: Routes.locationGate,
        builder: (_, _) => const LocationGatePage(),
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
            // The same `go`, for the same reason, carrying the number instead of
            // the address. The OTP screen reads whichever key is present.
            onSmsOtpSent: (String phone) => context.goNamed(
              Routes.otp,
              queryParameters: <String, String>{'phone': phone, 'from': ?from},
            ),
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'otp',
            name: Routes.otp,
            builder: (BuildContext context, GoRouterState state) {
              // Whichever one the sign-in screen put there. `OtpPage` asserts
              // exactly one is present, so a link carrying both — or neither —
              // fails loudly here rather than verifying a code against the
              // wrong channel and calling a good code invalid.
              final String? phone = state.uri.queryParameters['phone'];
              return phone != null
                  ? OtpPage(phone: phone)
                  : OtpPage(email: state.uri.queryParameters['email']!);
            },
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
          // Branch 3: Gifts — a second storefront beside food. Its own branch so
          // it keeps its stack and scroll position, and so a shop opened inside
          // it (the nested route below) stays under the Gifts tab.
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/gifts',
                name: Routes.gifts,
                builder: (BuildContext context, _) => GiftsPage(
                  onOpenShop: (GiftShop shop) => context.pushNamed(
                    Routes.giftShop,
                    pathParameters: <String, String>{'id': shop.id},
                  ),
                ),
                routes: <RouteBase>[
                  // Path-based, not `extra`-based: a shop must resolve from its
                  // id alone, with no Gifts feed in memory.
                  GoRoute(
                    path: 'shop/:id',
                    name: Routes.giftShop,
                    builder: (BuildContext context, GoRouterState state) =>
                        GiftShopPage(shopId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Cart
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

      GoRoute(
        path: '/favourites',
        name: Routes.favourites,
        builder: (_, _) => const FavouritesPage(),
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
            routes: <RouteBase>[
              // Nested under the order, so `/orders/ZPQ-1042/invoice` is a
              // link somebody can be sent and Back from it lands on the
              // receipt rather than on the history list.
              GoRoute(
                path: 'invoice',
                name: Routes.invoice,
                builder: (BuildContext context, GoRouterState state) =>
                    InvoicePage(orderId: state.pathParameters['id']!),
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
      // --- Gifts: bag, checkout, receipt, history -------------------------
      //
      // Top-level rather than nested under the shell's `/gifts` branch, and the
      // paths are hyphenated so they cannot collide with it. A bag and a
      // checkout want the whole screen — the bag docks its own checkout button
      // and the food cart learned the hard way that stacking a bar on a bottom
      // bar is a bar too many.
      GoRoute(
        path: '/gift-bag',
        name: Routes.giftBag,
        builder: (BuildContext context, _) => GiftBagPage(
          onCheckout: () => context.pushNamed(Routes.giftCheckout),
          onBrowse: () => context.goNamed(Routes.gifts),
        ),
      ),
      GoRoute(
        path: '/gift-checkout',
        name: Routes.giftCheckout,
        builder: (BuildContext context, _) => GiftCheckoutPage(
          // `go`, not `push`: nothing above the shell should survive a completed
          // checkout — the bag is empty and there is nothing to go back *to*.
          onPlaced: () => context.goNamed(Routes.giftPlaced),
          onBrowse: () => context.goNamed(Routes.gifts),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'placed',
            name: Routes.giftPlaced,
            builder: (BuildContext context, _) => GiftPlacedPage(
              onTrack: (String id) => context.goNamed(
                Routes.giftOrderDetail,
                pathParameters: <String, String>{'id': id},
              ),
              onBrowse: () => context.goNamed(Routes.gifts),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/gift-orders',
        name: Routes.giftOrders,
        builder: (BuildContext context, _) => GiftOrdersPage(
          onOpen: (String id) => context.pushNamed(
            Routes.giftOrderDetail,
            pathParameters: <String, String>{'id': id},
          ),
          onBrowse: () => context.goNamed(Routes.gifts),
        ),
        routes: <RouteBase>[
          // Nested, so a `go` here from the receipt builds the list underneath
          // and Back lands on the history rather than nowhere.
          GoRoute(
            path: ':id',
            name: Routes.giftOrderDetail,
            builder: (BuildContext context, GoRouterState state) =>
                GiftOrderDetailPage(
                  orderId: state.pathParameters['id']!,
                  onBack: () => context.goNamed(Routes.giftOrders),
                ),
          ),
        ],
      ),

      GoRoute(
        path: '/licenses',
        name: Routes.licenses,
        builder: (_, _) => const LicensesPage(),
      ),
      // The inbox. Deliberately not protected: a signed-out user simply has an
      // empty one (they have no user id to address a row to), and bouncing them
      // to a login screen to see "nothing yet" would be a worse welcome than the
      // empty list itself. The one tap that needs identity — opening an order —
      // is the order route, which is guarded on its own.
      GoRoute(
        path: '/notifications',
        name: Routes.notifications,
        builder: (_, _) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/account',
        name: Routes.account,
        builder: (_, _) => const AccountPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'profile',
            name: Routes.profile,
            builder: (_, _) => const ProfileDetailsPage(),
          ),
          GoRoute(
            path: 'delete',
            name: Routes.deleteAccount,
            builder: (_, _) => const DeleteAccountPage(),
          ),
          // `:doc` is 'privacy' or 'terms' — one screen, two documents, because
          // they differ only in which text they render.
          GoRoute(
            path: 'legal/:doc',
            name: Routes.legal,
            builder: (BuildContext context, GoRouterState state) =>
                LegalPage(document: state.pathParameters['doc'] ?? 'privacy'),
          ),
        ],
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
