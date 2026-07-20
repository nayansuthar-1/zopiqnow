import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/gifts/data/datasources/gift_datasource.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_shop_page.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gifts_page.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

/// A tiny gifts catalog: one shop with two items. Enough to prove the tab wires
/// the datasource to the browse grid and the shop page, without a network.
class _FakeGiftDataSource implements GiftDataSource {
  const _FakeGiftDataSource();

  static const GiftShop _shop = GiftShop(
    id: 'g1',
    name: 'Artisan Corner',
    tagline: 'Handcrafted homeware',
    description: 'Small-batch pottery and prints.',
    imageUrl: '',
    rating: 4.7,
    ratingCount: 1240,
  );

  static const List<GiftItem> _items = <GiftItem>[
    GiftItem(
      id: 'g1-i1',
      shopId: 'g1',
      name: 'Ceramic Bud Vase',
      description: 'Matte stoneware, thrown by hand.',
      price: 649,
      imageUrl: '',
      category: 'Home Decor',
      categoryRank: 0,
      itemRank: 0,
    ),
    GiftItem(
      id: 'g1-i2',
      shopId: 'g1',
      name: 'Wooden Photo Frame',
      description: 'Solid wood, soft finish.',
      price: 499,
      imageUrl: '',
      category: 'Home Decor',
      categoryRank: 0,
      itemRank: 1,
    ),
  ];

  @override
  Future<List<GiftShop>> fetchShops() async {
    await Future<void>.delayed(_latency);
    return const <GiftShop>[_shop];
  }

  @override
  Future<List<GiftItem>> fetchItems() async {
    await Future<void>.delayed(_latency);
    return _items;
  }

  @override
  Future<GiftShop?> fetchShopById(String id) async {
    await Future<void>.delayed(_latency);
    return id == _shop.id ? _shop : null;
  }

  @override
  Future<List<GiftItem>> fetchItemsByShop(String shopId) async {
    await Future<void>.delayed(_latency);
    return _items.where((GiftItem i) => i.shopId == shopId).toList();
  }
}

Widget _app() {
  return ProviderScope(
    overrides: <Override>[
      ...storageOverrides(),
      restaurantDataSourceProvider
          .overrideWithValue(const RestaurantMockDataSource(latency: _latency)),
      giftDataSourceProvider.overrideWithValue(const _FakeGiftDataSource()),
    ],
    child: const ZopiqApp(),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Reduce motion, as the OS setting would: Home's hero runs ambient loops that
  // would otherwise keep `pumpAndSettle` from ever settling while Home is
  // mounted (the shell's IndexedStack keeps it alive even on other tabs).
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Finder _tab(String label) => find.widgetWithText(GestureDetector, label);

void main() {
  testWidgets('the Gifts tab lists gift items and opens a shop',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    // The tab exists beside the food tabs.
    expect(find.text('Gifts'), findsOneWidget);

    await tester.tap(_tab('Gifts'));
    await tester.pumpAndSettle();

    expect(find.byType(GiftsPage), findsOneWidget);
    // Items from the fake catalog render in the browse grid.
    expect(find.text('Ceramic Bud Vase'), findsOneWidget);
    expect(find.text('Wooden Photo Frame'), findsOneWidget);
    // And the shop shows in the rail.
    expect(find.text('Artisan Corner'), findsWidgets);

    // Tapping the shop card opens its storefront page.
    await tester.tap(find.text('Artisan Corner').first);
    await tester.pumpAndSettle();

    expect(find.byType(GiftShopPage), findsOneWidget);
    // The shelf header (the category) and its items are on the page.
    expect(find.text('Home Decor'), findsWidgets);
  });

  testWidgets('tapping a gift opens its detail sheet',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(_tab('Gifts'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ceramic Bud Vase'));
    await tester.pumpAndSettle();

    // The sheet shows the item's description and price.
    expect(find.text('Matte stoneware, thrown by hand.'), findsOneWidget);
    expect(find.text('₹649'), findsWidgets);
  });
}
