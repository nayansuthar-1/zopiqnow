import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/about/presentation/licenses_page.dart';
import 'package:zopiqnow/features/account/presentation/pages/account_page.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/home_page.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

import '../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      ...storageOverrides(),
      restaurantDataSourceProvider
          .overrideWithValue(const RestaurantMockDataSource(latency: _latency)),
      menuDataSourceProvider
          .overrideWithValue(const MenuMockDataSource(latency: _latency)),
    ],
    child: const ZopiqApp(),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Reduce motion, exactly as the OS setting would: Home's hero banner runs
  // ambient looping animations that would otherwise keep `pumpAndSettle`
  // from ever settling while Home is mounted (the shell's IndexedStack keeps
  // it alive even on other tabs).
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The nav bar builds its tabs — and the cart pill — from [GestureDetector]s,
/// not the `InkResponse` of a stock `NavigationBar`.
Finder _tab(String label) => find.widgetWithText(GestureDetector, label);

/// The cart's item count, which the pill renders as a circled number beside the
/// word "Cart". Scoped to the pill: a "1" elsewhere on Home is not the badge.
Finder _cartCount(String count) => find.descendant(
  of: _tab('Cart'),
  matching: find.text(count),
);

void main() {
  testWidgets('starts on the Delivery tab', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomePage), findsOneWidget);
    // The first tab is "Delivery" — Home is what it shows, not what it is
    // called. Dining and Grocery sit beside it; Cart is the pill on the right.
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
  });

  testWidgets('the Cart tab shows the empty state and can return to Home',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(_tab('Cart'));
    await tester.pumpAndSettle();

    expect(find.byType(CartPage), findsOneWidget);
    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(find.text('Browse restaurants'));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('switching tabs preserves the Home scroll position',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('RECOMMENDED FOR YOU'), findsOneWidget);

    // Scroll that section off the top of the viewport.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('RECOMMENDED FOR YOU'), findsNothing);

    await tester.tap(_tab('Cart'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Delivery'));
    await tester.pumpAndSettle();

    // Still scrolled: an IndexedStack shell keeps the branch alive.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('RECOMMENDED FOR YOU'), findsNothing);
  });

  testWidgets('the cart badge tracks the item count',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    // An empty cart shows no count at all — not a "0".
    expect(_cartCount('0'), findsNothing);
    expect(_cartCount('1'), findsNothing);

    await tester.tap(find.text('Paradise Biryani').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MenuPage), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Signature Chicken Biryani'),
          matching: find.byType(MenuItemTile),
        ),
        matching: find.text('ADD'),
      ),
    );
    await tester.pumpAndSettle();

    // The menu sits above the shell, so go back to see the tab bar again.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_cartCount('1'), findsOneWidget);
  });

  testWidgets('the profile button opens the account page, which reaches the '
      'credits screen', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPage), findsOneWidget);

    await tester.tap(find.text('Licenses & credits'));
    await tester.pumpAndSettle();

    // The bundled licenses must be readable inside the shipped app, not just
    // in ATTRIBUTIONS.md.
    expect(find.byType(LicensesPage), findsOneWidget);
    expect(find.text('Microsoft Fluent Emoji'), findsOneWidget);
    expect(find.textContaining('MIT License'), findsOneWidget);
  });
}
