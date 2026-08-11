import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/cart/presentation/pages/cart_page.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/cart_bar.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

import '../../support/fake_stores.dart';
import '../../support/menu_navigation.dart';

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
  // from ever settling while Home is mounted below this flow's routes.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Settles the feed, the route transition, and the menu fetch. Avoids
/// `pumpAndSettle` while a shimmer is on screen — it never settles.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Opens a restaurant from the feed.
///
/// The feed is ordered by distance now and the list is lazy, so a named
/// restaurant is built only once it is near the viewport — `Paradise Biryani`
/// sits fourth at the fixtures' distances. The settle afterwards matters as
/// much as the scroll: a tap delivered while the list is still moving is
/// swallowed by the scrollable as a stop-the-fling gesture.
Future<void> _openRestaurant(WidgetTester tester, String name) async {
  if (find.text(name).evaluate().isEmpty) {
    // Back to the top first. `scrollUntilVisible` only ever scrolls one way,
    // and coming back from a menu leaves the feed wherever the last search left
    // it — which for the second restaurant in a flow is usually *past* the one
    // being looked for.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
    await tester.pumpAndSettle();

    if (find.text(name).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(name),
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }
  }
  await tester.tap(find.text(name).first);
}

/// The ADD button inside a specific dish's tile.
Finder _addButtonFor(String dishName) => find.descendant(
      of: find.ancestor(
        of: find.text(dishName),
        matching: find.byType(MenuItemTile),
      ),
      matching: find.text('ADD'),
    );

void main() {
  testWidgets('tapping a restaurant card opens its menu', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await _openRestaurant(tester, 'Paradise Biryani');
    await _settle(tester);

    expect(find.byType(MenuPage), findsOneWidget);
    expect(find.text('Signature Chicken Biryani'), findsOneWidget);
    // Vitals strip from the fetched restaurant, not from route `extra`.
    // This asserted on "for two" until 0101 took the cost-for-two line off the
    // header; the rating count proves the same thing — it is only ever read off
    // the fetched restaurant — and does not depend on a number the admin is no
    // longer asked for.
    expect(find.textContaining('ratings'), findsWidgets);
  });

  testWidgets('adding a dish reveals the cart bar and reaches the cart',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await _openRestaurant(tester, 'Paradise Biryani');
    await _settle(tester);

    // No cart bar until something is in the cart.
    expect(find.text('View cart'), findsNothing);

    await tester.tap(_addButtonFor('Signature Chicken Biryani'));
    await tester.pumpAndSettle();

    expect(find.byType(CartBar), findsOneWidget);
    expect(find.text('View cart'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('₹320'), findsWidgets);

    await tester.tap(find.text('View cart'));
    await tester.pumpAndSettle();

    expect(find.byType(CartPage), findsOneWidget);
    expect(find.text('To pay'), findsOneWidget);
    // 320 subtotal + 40 delivery + 16 tax. Shown twice by design: once in the
    // bill's "To pay" row, once on the checkout bar.
    expect(find.text('₹376'), findsNWidgets(2));
  });

  testWidgets('adding a dish from another restaurant prompts before clearing',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    // Fill a cart at Paradise Biryani.
    await _openRestaurant(tester, 'Paradise Biryani');
    await _settle(tester);
    await tester.tap(_addButtonFor('Signature Chicken Biryani'));
    await tester.pumpAndSettle();

    // Go back and open a different restaurant.
    await menuPageBack(tester);
    await tester.pumpAndSettle();
    await _openRestaurant(tester, 'Green Theory');
    await _settle(tester);

    await tester.tap(_addButtonFor('Signature Chicken Biryani'));
    await tester.pumpAndSettle();

    expect(find.text('Start a new cart?'), findsOneWidget);

    // Declining leaves the original cart untouched.
    await tester.tap(find.text('Keep my cart'));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('the Veg only switch hides non-vegetarian dishes',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await _openRestaurant(tester, 'Paradise Biryani');
    await _settle(tester);

    expect(find.text('Signature Chicken Biryani'), findsOneWidget); // non-veg
    expect(find.text('Paneer Butter Masala'), findsOneWidget); // veg

    // A chip in the menu's filter bar now, not a `Switch` — same provider
    // behind it (`vegOnlyProvider`), same effect on the list.
    await tester.tap(find.text('Veg only'));
    await _settle(tester);

    expect(find.text('Signature Chicken Biryani'), findsNothing);
    expect(find.text('Paneer Butter Masala'), findsOneWidget);
  });
}
