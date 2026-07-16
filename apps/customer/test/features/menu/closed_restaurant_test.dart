import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

/// A catalog of exactly one restaurant, which has paused orders. Both the feed
/// and the cold `fetchById` a menu deep-link uses return it, so the closed state
/// is exercised on every surface that reads a restaurant.
class _ClosedRestaurantDataSource implements RestaurantDataSource {
  const _ClosedRestaurantDataSource();

  static const Restaurant _closed = Restaurant(
    id: 'r1',
    name: 'Paradise Biryani',
    cuisines: <String>['Biryani', 'Hyderabadi'],
    rating: 4.4,
    ratingCount: 12800,
    etaMinutes: 32,
    priceForTwo: 500,
    distanceKm: 2.1,
    isVeg: false,
    imageUrl: 'https://foodish-api.com/images/biryani/biryani1.jpg',
    acceptingOrders: false,
  );

  @override
  Future<List<Restaurant>> fetchNearby() async => const <Restaurant>[_closed];

  @override
  Future<Restaurant?> fetchById(String id) async => _closed;

  @override
  Future<List<Restaurant>> search(String query) async =>
      const <Restaurant>[_closed];
}

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      ...storageOverrides(),
      restaurantDataSourceProvider.overrideWithValue(
        const _ClosedRestaurantDataSource(),
      ),
      menuDataSourceProvider.overrideWithValue(
        const MenuMockDataSource(latency: _latency),
      ),
    ],
    child: const ZopiqApp(),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _addButtonFor(String dishName) => find.descendant(
  of: find.ancestor(
    of: find.text(dishName),
    matching: find.byType(MenuItemTile),
  ),
  matching: find.text('ADD'),
);

void main() {
  testWidgets('a closed restaurant says so on its card', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    // The scrim over the card image, so "closed" is the first thing read.
    expect(find.text('Closed for now'), findsOneWidget);
  });

  testWidgets('a closed restaurant\'s menu explains itself and refuses ADD', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Paradise Biryani').first);
    await _settle(tester);

    expect(find.byType(MenuPage), findsOneWidget);
    // The banner that explains the greyed-out buttons below it.
    expect(
      find.textContaining('paused orders'),
      findsOneWidget,
    );

    // The ADD control is inert: tapping it adds nothing, so the cart bar never
    // appears. The button is greyed (IgnorePointer), so the tap falls through.
    await tester.tap(
      _addButtonFor('Signature Chicken Biryani'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // The cart bar lives in the menu's bottomNavigationBar at all times but shows
    // nothing until the cart has something in it — so an empty cart is the
    // absence of its "View cart" call to action, which is what a blocked ADD
    // leaves behind.
    expect(find.text('View cart'), findsNothing);
  });
}
