import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/pages/email_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/otp_page.dart';
import 'package:zopiqnow/features/auth/presentation/pages/splash_page.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

import '../../support/fake_auth_datasource.dart';
import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const String _email = 'diner@example.com';

/// A session Supabase has already restored — what a returning user has.
const AuthUser _restoredUser = AuthUser(
  id: 'usr_1',
  email: _email,
  phone: '+919876543210',
);

/// A cart with something in it — what a customer has when they hit the guard.
/// "Proceed to checkout" does not exist on an empty cart.
const Cart _seededCart = Cart(
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  lines: <CartLine>[
    CartLine(
      item: MenuItem(
        id: 'r1-m1',
        name: 'Signature Chicken Biryani',
        description: '',
        price: 320,
        isVeg: false,
      ),
      quantity: 1,
    ),
  ],
);

class _SeededCartNotifier extends CartNotifier {
  @override
  Cart build() => _seededCart;
}

/// Uses the *real* [AuthController] (`authState: null`) so the async session
/// restore, the splash, and the redirect all actually run.
ProviderContainer _container({AuthUser? signedInAs, Cart? cart}) =>
    ProviderContainer(
      overrides: <Override>[
        ...storageOverrides(
          authState: null,
          authDataSource: FakeAuthDataSource(signedInAs: signedInAs),
        ),
        restaurantDataSourceProvider.overrideWithValue(
          const RestaurantMockDataSource(latency: _latency),
        ),
        if (cart != null) cartProvider.overrideWith(_SeededCartNotifier.new),
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

/// Signs in from the login screen: address, then code.
Future<void> _signIn(WidgetTester tester, {required String code}) async {
  await tester.enterText(
    find.descendant(of: find.byType(EmailPage), matching: find.byType(TextField)),
    _email,
  );
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester);

  // Six digits auto-submits.
  await tester.enterText(
    find.descendant(of: find.byType(OtpPage), matching: find.byType(TextField)),
    code,
  );
  await _settle(tester);
}

void main() {
  testWidgets('a cold start shows the splash until the session resolves', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));

    // First frame: the session read has not returned, so we must not have
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
    expect(find.byType(EmailPage), findsNothing);
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

    expect(find.byType(EmailPage), findsOneWidget);
    expect(find.byType(CheckoutPage), findsNothing);
    // The intended destination is carried, not discarded.
    expect(_location(container), contains('from=%2Fcheckout'));
  });

  testWidgets('verifying the code returns the user to the intended route', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    await _signIn(tester, code: FakeAuthDataSource.devCode);

    // Not Home — /checkout, which is where they were going.
    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(_location(container), '/checkout');
    // And the OTP screen is *gone*, not merely covered by the destination.
    // Reaching the right location is not enough: an imperatively pushed route
    // outlives the redirect that replaced its location, so the user would still
    // be looking at a Verify button that spins forever. Only this assertion
    // catches that — the one above passes either way.
    expect(find.byType(OtpPage), findsNothing);
  });

  testWidgets('signing in from Account leaves the login flow behind', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    // Account opens login *imperatively* — the guard is not involved, because
    // /account is not protected. This is the path a user actually takes, and it
    // is the one that broke: a pushed route outlives the redirect that replaces
    // its location, so the OTP screen stayed on top of Home, spinning forever.
    unawaited(container.read(routerProvider).push('/login'));
    await _settle(tester);

    await _signIn(tester, code: FakeAuthDataSource.devCode);

    expect(find.byType(OtpPage), findsNothing);
    expect(find.byType(EmailPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });

  group('the guard fires on the path a user actually takes', () {
    // Every other test in this file reaches /checkout with `router.go`. Nobody
    // does that. A real customer builds a cart and taps "Proceed to checkout",
    // and that button *pushes* — which is the whole bug: go_router does not
    // re-run `redirect` on an imperatively pushed route, so the login the guard
    // put there outlives the sign-in that was supposed to replace it. The user
    // picks a Google account, watches nothing happen, and finds themselves
    // signed in only after pressing back.
    Future<void> proceedToCheckout(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(GestureDetector, 'Cart'));
      await _settle(tester);
      await tester.tap(find.text('Proceed to checkout'));
      await _settle(tester);
    }

    testWidgets('signing in with Google from the checkout guard lands on '
        'checkout', (WidgetTester tester) async {
      final ProviderContainer container = _container(cart: _seededCart);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await proceedToCheckout(tester);

      expect(find.byType(EmailPage), findsOneWidget);

      await tester.tap(find.text('Continue with Google'));
      await _settle(tester);

      expect(find.byType(CheckoutPage), findsOneWidget);
      // The login screen is *gone*, not merely covered: the location assertion
      // alone would pass while the user still stares at the sign-in page.
      expect(find.byType(EmailPage), findsNothing);
      expect(_location(container), '/checkout');
    });

    testWidgets('signing in with an email code from the checkout guard lands '
        'on checkout', (WidgetTester tester) async {
      final ProviderContainer container = _container(cart: _seededCart);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await proceedToCheckout(tester);

      await _signIn(tester, code: FakeAuthDataSource.devCode);

      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(find.byType(OtpPage), findsNothing);
      expect(find.byType(EmailPage), findsNothing);
    });

    testWidgets('backing out of the guard returns to the cart, not a dead end', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = _container(cart: _seededCart);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await proceedToCheckout(tester);

      await tester.tap(find.byIcon(Icons.close));
      await _settle(tester);

      // Home, not the route that demanded a login — that would bounce straight
      // back here forever.
      expect(find.byType(EmailPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });
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

    await _signIn(tester, code: '000000');

    expect(find.byType(OtpPage), findsOneWidget);
    expect(find.text('That code is not right. Try again.'), findsOneWidget);
    expect(find.byType(CheckoutPage), findsNothing);
  });

  testWidgets('a restored session opens /checkout without a login', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container(signedInAs: _restoredUser);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(find.byType(EmailPage), findsNothing);
  });

  testWidgets('a cold deep link to /checkout survives the session restore', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container(signedInAs: _restoredUser);
    addTearDown(container.dispose);

    // Navigate before the restore has resolved — the splash must remember it.
    await tester.pumpWidget(_app(container));
    container.read(routerProvider).go('/checkout');
    await _settle(tester);

    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(_location(container), '/checkout');
  });
}
