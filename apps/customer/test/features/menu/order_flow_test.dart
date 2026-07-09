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

    await tester.tap(find.text('Paradise Biryani').first);
    await _settle(tester);

    expect(find.byType(MenuPage), findsOneWidget);
    expect(find.text('Signature Chicken Biryani'), findsOneWidget);
    // Vitals strip from the fetched restaurant, not from route `extra`.
    expect(find.textContaining('for two'), findsWidgets);
  });

  testWidgets('adding a dish reveals the cart bar and reaches the cart',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Paradise Biryani').first);
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
    await tester.tap(find.text('Paradise Biryani').first);
    await _settle(tester);
    await tester.tap(_addButtonFor('Signature Chicken Biryani'));
    await tester.pumpAndSettle();

    // Go back and open a different restaurant.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Green Theory').first);
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

    await tester.tap(find.text('Paradise Biryani').first);
    await _settle(tester);

    expect(find.text('Signature Chicken Biryani'), findsOneWidget); // non-veg
    expect(find.text('Paneer Butter Masala'), findsOneWidget); // veg

    await tester.tap(find.byType(Switch));
    await _settle(tester);

    expect(find.text('Signature Chicken Biryani'), findsNothing);
    expect(find.text('Paneer Butter Masala'), findsOneWidget);
  });
}
