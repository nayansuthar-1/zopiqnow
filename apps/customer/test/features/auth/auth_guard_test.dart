import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/data/datasources/auth_mock_datasource.dart';
import 'package:zopiqnow/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/phone_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

/// A signed-in session, exactly as [AuthRepositoryImpl] writes it.
const Map<String, String> _storedSession = <String, String>{
  'zopiq.auth.session':
      '{"userId":"usr_1","phone":"+919876543210",'
      '"accessToken":"a","refreshToken":"r"}',
};

/// Uses the *real* [AuthController] (`authState: null`) so the async session
/// restore, the splash, and the redirect all actually run. The secure store is
/// given a real delay so the restore cannot complete before the first frame.
ProviderContainer _container({Map<String, String>? session}) =>
    ProviderContainer(
      overrides: <Override>[
        ...storageOverrides(
          authState: null,
          secureStore: FakeSecureStore(session, _latency),
        ),
        restaurantDataSourceProvider.overrideWithValue(
          const RestaurantMockDataSource(latency: _latency),
        ),
      ],
    );

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const ZopiqApp());

/// Enough frames for the restore microtask, the redirect, and the route
/// transition. Never `pumpAndSettle` — Home's shimmer never settles.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(); // schedule the async restore / repository call
  await tester.pump(const Duration(milliseconds: 50)); // it completes, redirect
  await tester.pump(const Duration(milliseconds: 500)); // incoming route lands
  // The outgoing route's exit only *begins* on the frame after the redirect, so
  // it needs a second window before the Navigator drops it from the tree.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

String _location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('a cold start shows the splash until the session resolves', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));

    // First frame: the Keystore read has not returned, so we must not have
    // guessed. Redirecting to Home or Login here would be the bug.
    expect(find.byType(SplashPage), findsOneWidget);

    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing);
  });

  testWidgets('browsing needs no account', (WidgetTester tester) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    // Signed out, yet Home renders. Search and cart are open too.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(PhonePage), findsNothing);
  });

  testWidgets('a signed-out user hitting /checkout is sent to login', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    expect(find.byType(PhonePage), findsOneWidget);
    expect(find.byType(CheckoutPage), findsNothing);
    // The intended destination is carried, not discarded.
    expect(_location(container), contains('from=%2Fcheckout'));
  });

  testWidgets('verifying the OTP returns the user to the intended route', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.byType(OtpPage), findsOneWidget);

    // Six digits auto-submits.
    await tester.enterText(
      find.descendant(
        of: find.byType(OtpPage),
        matching: find.byType(TextField),
      ),
      AuthMockDataSource.devCode,
    );
    await _settle(tester);

    // Not Home — /checkout, which is where they were going.
    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(_location(container), '/checkout');
  });

  testWidgets('a wrong code keeps the user on the OTP screen', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);
    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(OtpPage),
        matching: find.byType(TextField),
      ),
      '000000',
    );
    await _settle(tester);

    expect(find.byType(OtpPage), findsOneWidget);
    expect(find.text('That code is not right. Try again.'), findsOneWidget);
    expect(find.byType(CheckoutPage), findsNothing);
  });

  testWidgets('a restored session opens /checkout without a login', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container(session: _storedSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(find.byType(PhonePage), findsNothing);
  });

  testWidgets('a cold deep link to /checkout survives the session restore', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container(session: _storedSession);
    addTearDown(container.dispose);

    // Navigate before the restore has resolved — the splash must remember it.
    await tester.pumpWidget(_app(container));
    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(_location(container), '/checkout');
  });
}
