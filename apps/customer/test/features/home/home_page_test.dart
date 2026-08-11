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

/// A card-scoped finder. It stays card-scoped even though the top-chains rail
/// that used to duplicate these names is gone from Home: the finder is about
/// asserting on the *list*, and a dish rail could put a restaurant's name back
/// on the screen tomorrow.
Finder _cardNamed(String name) => find.descendant(
      of: find.byType(RestaurantCard),
      matching: find.text(name),
    );

/// The feed is ordered by distance from the selected address now, and the list
/// is lazy — so a named restaurant is built only once it is near the viewport.
/// At the fixtures' distances `Paradise Biryani` sits fourth, off the bottom of
/// even a tall test surface, and a bare `find.text` for it finds nothing.
///
/// Scrolling to it rather than growing the surface again: a viewport tall
/// enough to build every card is also one nothing can be scrolled *off*, which
/// is the assertion the shell's scroll-position test depends on.
Future<void> _scrollToCard(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    _cardNamed(name),
    300,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

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
    await _scrollToCard(tester, 'Paradise Biryani');
    expect(_cardNamed('Paradise Biryani'), findsOneWidget);
  });

  testWidgets('renders merchandising above the feed while it is still loading',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 200))),
    );

    // Categories and chips are static: they are on screen during the first
    // frame, while the restaurant feed is still loading. (The rail's old
    // "What's on your mind?" heading went with the Home revamp — the categories
    // themselves are the point, and they are still here.)
    expect(find.byType(FoodCategoryRail), findsOneWidget);
    expect(find.byType(HomeFilterChips), findsOneWidget);
    expect(find.text('Pizza'), findsOneWidget);

    // The feed-derived half of this case used to be the top-chains rail. Home
    // no longer builds one — `_RecommendedDishesSection` took its place, and it
    // ranks *dishes* off a Supabase read that a widget test has no seam for, so
    // it renders nothing here and asserting on it would be asserting on the
    // absence of a network. What survives is the claim that actually failed
    // when it was broken: the count header appears with the feed and not
    // before, so merchandising does not wait on the list.
    expect(find.textContaining('RESTAURANTS DELIVERING'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('RESTAURANTS DELIVERING'), findsOneWidget);
  });

  testWidgets('the Pure Veg chip filters the list',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(const RestaurantMockDataSource(latency: Duration(milliseconds: 10))),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await _scrollToCard(tester, 'Paradise Biryani');
    expect(_cardNamed('Paradise Biryani'), findsOneWidget); // non-veg

    // The chips sit in a pinned header, so they are still on screen after the
    // scroll above — which is the whole point of pinning them.
    await tester.tap(_chipNamed('Pure Veg'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_cardNamed('Paradise Biryani'), findsNothing);

    // Back to the top to see what survived. Filtering does not rewind the list
    // for us — the offset we scrolled to in order to reach the non-veg card is
    // still past the three veg ones that remain.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_cardNamed('Green Theory'), findsOneWidget); // veg
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
