import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiq_vendor/app/vendor_shell.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/not_staff_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/sign_in_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/manage_categories_page.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiq_vendor/features/orders/presentation/pages/history_page.dart';
import 'package:zopiq_vendor/features/orders/presentation/pages/queue_page.dart';
import 'package:zopiq_vendor/features/profile/presentation/pages/profile_edit_page.dart';
import 'package:zopiq_vendor/features/profile/presentation/pages/profile_page.dart';

abstract final class Routes {
  static const String queue = 'queue';
  static const String history = 'history';
  static const String menu = 'menu';
  static const String menuCategories = 'menuCategories';
  static const String profile = 'profile';
  static const String profileEdit = 'profileEdit';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String notStaff = 'notStaff';
}

const String _ordersPath = '/orders';
const String _splashPath = '/splash';
const String _loginPath = '/login';
const String _notStaffPath = '/not-a-partner';

/// Bridges Riverpod's auth state to the [Listenable] GoRouter wants. Without it,
/// signing in changes state but never re-runs `redirect`.
///
/// Fires only when the auth *class* changes, not on every emission. The redirect
/// below branches on which of the four states applies and nothing inside them,
/// so a change within a state — a restaurant renamed, `AuthSignedIn` to
/// `AuthSignedIn` — cannot change where anyone is sent. Refreshing on it anyway
/// rebuilds the route stack under the user's feet, which pops an imperatively
/// pushed page (the profile editor) out from under a `Navigator.pop` mid-save.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<VendorAuthState>(vendorAuthControllerProvider, (
      VendorAuthState? previous,
      VendorAuthState next,
    ) {
      if (previous.runtimeType != next.runtimeType) notifyListeners();
    });
  }
}

/// The whole app is behind the guard, and that is the difference from the
/// customer app.
///
/// A customer may browse, search and build a cart without an account — identity
/// is only required where money and an address are. There is no equivalent here:
/// every screen in this app is somebody's order book. There is nothing to show a
/// stranger, so there is no unguarded route to show them.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshListenable refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: _ordersPath,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final VendorAuthState auth = ref.read(vendorAuthControllerProvider);
      final String location = state.matchedLocation;
      final bool onAuthRoute = location.startsWith(_loginPath);

      return switch (auth) {
        // The session is still being read from the Keystore. Park on the splash.
        // Redirecting now would bounce a signed-in kitchen to the login screen
        // on every cold start.
        AuthUnknown() => location == _splashPath ? null : _splashPath,

        // Authenticated, and nobody. Not an error — a screen.
        AuthNotStaff() => location == _notStaffPath ? null : _notStaffPath,

        AuthSignedOut() => onAuthRoute ? null : _loginPath,

        // Signing in is what leaves the login screen. The OTP page never pops
        // itself — see its class doc.
        AuthSignedIn() =>
          onAuthRoute || location == _splashPath || location == _notStaffPath
              ? _ordersPath
              : null,
      };
    },
    routes: <RouteBase>[
      // The four rooms of the app, held in a bottom-nav shell. Each keeps its own
      // navigation stack and scroll position (indexedStack).
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) => VendorShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: _ordersPath,
                name: Routes.queue,
                builder: (_, _) => const QueuePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                name: Routes.history,
                builder: (_, _) => const HistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/menu',
                name: Routes.menu,
                builder: (_, _) => const MenuPage(),
                routes: <RouteBase>[
                  // Pushed over the menu tab, like the profile editor: a back
                  // button, and the bottom nav stays put.
                  GoRoute(
                    path: 'categories',
                    name: Routes.menuCategories,
                    builder: (_, _) => const ManageCategoriesPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                name: Routes.profile,
                builder: (_, _) => const ProfilePage(),
                routes: <RouteBase>[
                  // Pushed over the profile tab, inside its branch — the form has
                  // a back button and the bottom nav stays put.
                  GoRoute(
                    path: 'edit',
                    name: Routes.profileEdit,
                    builder: (_, _) => const ProfileEditPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: _splashPath,
        name: Routes.splash,
        builder: (_, _) => const SplashPage(),
      ),
      GoRoute(
        path: _notStaffPath,
        name: Routes.notStaff,
        builder: (BuildContext context, GoRouterState state) {
          final VendorAuthState auth = ref.read(vendorAuthControllerProvider);
          return NotStaffPage(email: auth is AuthNotStaff ? auth.email : '');
        },
      ),
      GoRoute(
        path: _loginPath,
        name: Routes.login,
        builder: (BuildContext context, GoRouterState state) => SignInPage(
          // `go`, never `push`. A pushed route sits above the location the
          // router holds, and no redirect can take it back down: signing in
          // would move the router to the queue while the OTP screen stayed on
          // top, spinning forever.
          onOtpSent: (String email) => context.goNamed(
            Routes.otp,
            queryParameters: <String, String>{'email': email},
          ),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'otp',
            name: Routes.otp,
            builder: (BuildContext context, GoRouterState state) =>
                OtpPage(email: state.uri.queryParameters['email']!),
          ),
        ],
      ),
    ],
  );
});
