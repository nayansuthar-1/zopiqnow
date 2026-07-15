import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiq_vendor/features/auth/presentation/pages/not_staff_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/sign_in_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiq_vendor/features/orders/presentation/pages/queue_page.dart';

abstract final class Routes {
  static const String queue = 'queue';
  static const String menu = 'menu';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String notStaff = 'notStaff';
}

const String _splashPath = '/splash';
const String _loginPath = '/login';
const String _notStaffPath = '/not-a-partner';

/// Bridges Riverpod's auth state to the [Listenable] GoRouter wants. Without it,
/// signing in changes state but never re-runs `redirect`.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<VendorAuthState>(
      vendorAuthControllerProvider,
      (VendorAuthState? _, VendorAuthState _) => notifyListeners(),
    );
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
    initialLocation: '/',
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
              ? '/'
              : null,
      };
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: Routes.queue,
        builder: (_, _) => const QueuePage(),
        routes: <RouteBase>[
          // A child of the queue, so it pushes over it with a back button and
          // stays behind the same auth guard — there is no signed-out route to
          // a restaurant's menu.
          GoRoute(
            path: 'menu',
            name: Routes.menu,
            builder: (_, _) => const MenuPage(),
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
