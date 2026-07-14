import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/presentation/pages/menu_page.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/search/presentation/providers/search_providers.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

/// Long enough for the debounce to elapse.
const Duration _afterDebounce = Duration(milliseconds: 400);

/// Drains the two-stage wait a search goes through: the debounce timer, then the
/// repository's own latency, then the frame that paints the result. One pump per
/// stage — `pumpAndSettle` is unsafe here because the loading shimmer never
/// settles.
Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump(); // rebuild after the keystroke; provider arms the debounce
  await tester.pump(_afterDebounce); // debounce fires, repo call starts
  await tester.pump(const Duration(milliseconds: 50)); // repo latency elapses
  await tester.pump(); // rebuild with the results
}

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
  // Reduce motion, as the OS setting would. Search is pushed *over* Home, which
  // stays mounted and keeps looping its hero banner — so without this,
  // `pumpAndSettle` never settles once Search is open.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Search has no tab any more: it opens from the pill in Home's header, which is
/// the only way into it that a user actually has.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('Search "Biryani"'));
  await tester.pumpAndSettle();
}

void main() {
  group('mock data source', () {
    const RestaurantMockDataSource source =
        RestaurantMockDataSource(latency: Duration.zero);

    test('a blank query returns nothing, not the whole catalogue', () async {
      expect(await source.search(''), isEmpty);
      expect(await source.search('   '), isEmpty);
    });

    test('matches restaurant names case-insensitively', () async {
      final List<Restaurant> found = await source.search('PARADISE');
      expect(found.single.name, 'Paradise Biryani');
    });

    test('matches cuisines, not just names', () async {
      // No restaurant is called "Sushi"; Sushi Ninja matches on cuisine.
      final List<Restaurant> found = await source.search('sushi');
      expect(found.single.name, 'Sushi Ninja');
    });

    test('an unmatched query returns an empty list', () async {
      expect(await source.search('zzzz'), isEmpty);
    });
  });

  group('recent searches', () {
    late FakeKeyValueStore store;
    late ProviderContainer container;

    /// A container over [store] — a second one is the next app launch, reading
    /// the same prefs the first one wrote.
    ProviderContainer launch() {
      final ProviderContainer c = ProviderContainer(
        overrides: storageOverrides(keyValueStore: store),
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      store = FakeKeyValueStore();
      container = launch();
    });

    RecentSearchesNotifier notifier() =>
        container.read(recentSearchesProvider.notifier);
    List<String> recents() => container.read(recentSearchesProvider);

    test('records most-recent-first and de-duplicates case-insensitively', () {
      notifier().record('biryani');
      notifier().record('pizza');
      notifier().record('BIRYANI');

      expect(recents(), <String>['BIRYANI', 'pizza']);
    });

    test('ignores blank queries', () {
      notifier().record('   ');
      expect(recents(), isEmpty);
    });

    test('keeps only the five most recent', () {
      for (final String q in <String>['a', 'b', 'c', 'd', 'e', 'f']) {
        notifier().record(q);
      }
      expect(recents(), <String>['f', 'e', 'd', 'c', 'b']);
    });

    test('survives a restart', () {
      notifier().record('biryani');
      notifier().record('pizza');

      // The next app launch, over the same prefs. A "recent" search that forgets
      // itself on close is a list of what you did five minutes ago — which you
      // already remember.
      expect(
        launch().read(recentSearchesProvider),
        <String>['pizza', 'biryani'],
      );
    });

    test('clearing them clears the stored copy too', () {
      notifier().record('biryani');
      notifier().clear();

      expect(launch().read(recentSearchesProvider), isEmpty);
    });

    test('a corrupt stored history is ignored, not thrown', () {
      store = FakeKeyValueStore(<String, String>{
        'zopiq.search.recent': '{"not":"a list"}',
      });
      expect(launch().read(recentSearchesProvider), isEmpty);
    });
  });

  testWidgets('the empty-query state prompts, then results appear',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await _openSearch(tester);

    expect(find.text('What are you craving?'), findsOneWidget);
    expect(find.byType(RestaurantCard), findsNothing);

    await tester.enterText(find.byType(TextField), 'biryani');
    await _settleSearch(tester);

    expect(find.byType(RestaurantCard), findsOneWidget);
    expect(find.text('Paradise Biryani'), findsOneWidget);
  });

  testWidgets('debounce collapses a burst of keystrokes into one search',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await _openSearch(tester);

    // Type fast: no keystroke pauses long enough for the debounce to fire.
    for (final String partial in <String>['b', 'bi', 'bir', 'biry']) {
      await tester.enterText(find.byType(TextField), partial);
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Still nothing fetched — the debounce has not elapsed since the last key.
    expect(find.byType(RestaurantCard), findsNothing);

    await _settleSearch(tester);
    expect(find.text('Paradise Biryani'), findsOneWidget);
  });

  testWidgets('an unmatched query shows a no-results state, not an error',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await _openSearch(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await _settleSearch(tester);

    expect(find.text('No results for "zzzz"'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  // Regression: Home and Search are both mounted in the shell's IndexedStack,
  // so a restaurant appearing in both once registered two Heroes under one tag
  // and threw "multiple heroes share the same tag" on the route transition.
  testWidgets('opening a result records it and reaches the menu',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    await _openSearch(tester);

    await tester.enterText(find.byType(TextField), 'biryani');
    await _settleSearch(tester);

    await tester.tap(find.text('Paradise Biryani'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MenuPage), findsOneWidget);

    // Back on Search, the query is remembered.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('biryani'), findsOneWidget);
  });
}
