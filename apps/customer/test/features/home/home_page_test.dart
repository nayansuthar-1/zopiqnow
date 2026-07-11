import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/food_category_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_filter_chips.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';
import 'package:zopiqnow/features/home/presentation/widgets/top_chains_rail.dart';

import '../../support/fake_stores.dart';

Widget _app(RestaurantMockDataSource dataSource) {
  return ProviderScope(
    overrides: <Override>[
      ...storageOverrides(),
      restaurantDataSourceProvider.overrideWithValue(dataSource),
    ],
    child: const ZopiqApp(),
  );
}

/// Home now stacks a header, an offers carousel, two rails and a chip row above
/// the restaurant list, so the default 800x600 test surface never reaches the
/// list at all. Give each test a tall viewport instead of scrolling in every one.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A card-scoped finder: `Paradise Biryani` also appears in the top-chains rail,
/// so bare `find.text` cannot tell the list apart from the rail.
Finder _cardNamed(String name) => find.descendant(
      of: find.byType(RestaurantCard),
      matching: find.text(name),
    );

Finder _chipNamed(String label) => find.descendant(
      of: find.byType(HomeFilterChips),
      matching: find.text(label),
    );

void main() {
  testWidgets('shows shimmer while loading, then the restaurant list',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 200))),
    );

    // First frame: the feed is loading → skeleton, no cards yet.
    expect(find.byType(RestaurantListSkeleton), findsOneWidget);
    expect(find.byType(RestaurantCard), findsNothing);

    // Let the mock future resolve (not pumpAndSettle: shimmer never settles).
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RestaurantListSkeleton), findsNothing);
    expect(find.byType(RestaurantCard), findsWidgets);
    expect(_cardNamed('Paradise Biryani'), findsOneWidget);
  });

  testWidgets('renders merchandising rails independently of the feed',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 200))),
    );

    // Categories and chips are static: they are on screen during the first
    // frame, while the restaurant feed is still loading.
    expect(find.byType(FoodCategoryRail), findsOneWidget);
    expect(find.byType(HomeFilterChips), findsOneWidget);
    expect(find.text("What's on your mind?"), findsOneWidget);

    // The top-chains rail derives from the feed, so it only appears after load.
    expect(find.byType(TopChainsRail), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TopChainsRail), findsOneWidget);
  });

  testWidgets('the Pure Veg chip filters the list but not the top-chains rail',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 10))),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(_cardNamed('Paradise Biryani'), findsOneWidget); // non-veg
    expect(_cardNamed('Green Theory'), findsOneWidget); // veg

    await tester.tap(_chipNamed('Pure Veg'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_cardNamed('Paradise Biryani'), findsNothing);
    expect(_cardNamed('Green Theory'), findsOneWidget);

    // The rail is deliberately unfiltered, so the non-veg chain is still there.
    expect(
      find.descendant(
        of: find.byType(TopChainsRail),
        matching: find.text('Paradise Biryani'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a retryable error state when the feed fails',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(
        latency: Duration(milliseconds: 10),
        shouldFail: true,
      )),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeErrorView), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(RestaurantCard), findsNothing);
  });
}
