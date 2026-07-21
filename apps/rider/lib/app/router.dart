import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zopiq_rider/features/auth/presentation/pages/auth_pages.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/presentation/pages/home_page.dart';

abstract final class Routes {
  static const String home = 'home';
  static const String splash = 'splash';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String notPartner = 'notPartner';
}

const String _homePath = '/jobs';
const String _splashPath = '/splash';
const String _loginPath = '/login';
const String _notPartnerPath = '/not-a-partner';

/// Bridges Riverpod's auth state to the [Listenable] GoRouter wants.
///
/// Fires only when the auth *class* changes, not on every emission — the
/// redirect below branches on which of the four states applies and nothing
/// inside them, so a change within a state cannot change where anyone is sent.
/// Refreshing anyway would rebuild the route stack under the rider's feet.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<RiderAuthState>(riderAuthControllerProvider, (
      RiderAuthState? previous,
      RiderAuthState next,
    ) {
      if (previous.runtimeType != next.runtimeType) notifyListeners();
    });
  }
}

/// The whole app is behind the guard, like the vendor app and unlike the
/// customer one. There is nothing here to show a stranger — every screen is
/// somebody's address.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshListenable refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: _homePath,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final RiderAuthState auth = ref.read(riderAuthControllerProvider);
      final String location = state.matchedLocation;
      final bool onAuthRoute = location.startsWith(_loginPath);

      return switch (auth) {
        AuthUnknown() => location == _splashPath ? null : _splashPath,
        AuthNotPartner() => location == _notPartnerPath ? null : _notPartnerPath,
        AuthSignedOut() => onAuthRoute ? null : _loginPath,
        AuthSignedIn() =>
          onAuthRoute || location == _splashPath || location == _notPartnerPath
              ? _homePath
              : null,
      };
    },
    routes: <RouteBase>[
      GoRoute(
        path: _homePath,
        name: Routes.home,
        builder: (_, _) => const HomePage(),
      ),
      GoRoute(
        path: _splashPath,
        name: Routes.splash,
        builder: (_, _) => const SplashPage(),
      ),
      GoRoute(
        path: _notPartnerPath,
        name: Routes.notPartner,
        builder: (BuildContext context, GoRouterState state) {
          final RiderAuthState auth = ref.read(riderAuthControllerProvider);
          return NotPartnerPage(
            email: auth is AuthNotPartner ? auth.email : '',
          );
        },
      ),
      GoRoute(
        path: _loginPath,
        name: Routes.login,
        builder: (BuildContext context, GoRouterState state) => SignInPage(
          // `go`, never `push`. A pushed route sits above the location the
          // router holds and no redirect can take it back down: signing in
          // would move the router to the board while the OTP screen stayed on
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
