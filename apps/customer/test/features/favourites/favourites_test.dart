import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/pages/email_page.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_mock_datasource.dart';
import 'package:zopiqnow/features/favourites/domain/repositories/favourites_repository.dart';
import 'package:zopiqnow/features/favourites/presentation/pages/favourites_page.dart';
import 'package:zopiqnow/features/favourites/presentation/providers/favourites_providers.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

import '../../support/fake_auth_datasource.dart';
import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const AuthUser _user = AuthUser(id: 'usr_1', email: 'diner@example.com');

/// A data source whose writes always fail — the flaky network, so the optimistic
/// heart has something to roll back from.
class _FailingFavourites implements FavouritesDataSource {
  @override
  Future<List<Restaurant>> fetchFavourites() async => const <Restaurant>[];

  @override
  Future<void> addFavourite(String restaurantId) async =>
      throw Exception('network');

  @override
  Future<void> removeFavourite(String restaurantId) async =>
      throw Exception('network');
}

ProviderContainer _container({
  FavouritesDataSource? favourites,
  AuthState authState = const AuthSignedIn(_user),
}) => ProviderContainer(
  overrides: <Override>[
    ...storageOverrides(
      authState: authState,
      authDataSource: FakeAuthDataSource(
        signedInAs: authState is AuthSignedIn ? _user : null,
      ),
      favouritesDataSource: favourites ?? FavouritesMockDataSource(),
    ),
    restaurantDataSourceProvider.overrideWithValue(
      const RestaurantMockDataSource(latency: _latency),
    ),
  ],
);

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const ZopiqApp());

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The heart on the first restaurant card in the feed.
Finder _firstHeart() => find.byIcon(Icons.favorite_border_rounded).first;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('the heart', () {
    testWidgets('fills on tap and saves the restaurant', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      expect(container.read(favouritesProvider).valueOrNull, isEmpty);

      await tester.tap(_firstHeart());
      await _settle(tester);

      final List<Restaurant> saved =
          container.read(favouritesProvider).valueOrNull!;
      expect(saved, hasLength(1));
      // Filled, not outlined — the heart is the whole feedback.
      expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
    });

    testWidgets('a failed save puts the heart back, and says why', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        favourites: _FailingFavourites(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      await tester.tap(_firstHeart());
      await _settle(tester);

      // Optimism is not a licence to lie: the write failed, so the heart is
      // empty again and the customer is told, rather than left looking at a
      // favourite the server never accepted.
      expect(container.read(favouritesProvider).valueOrNull, isEmpty);
      expect(find.text('We couldn\'t save that favourite.'), findsOneWidget);
    });

    testWidgets('a signed-out tap opens the login rather than doing nothing', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        authState: const AuthSignedOut(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);

      await tester.tap(_firstHeart());
      await _settle(tester);

      // A favourite belongs to an account. Someone tapping the heart is telling
      // us they want it saved — silently swallowing that is the worst answer.
      expect(find.byType(EmailPage), findsOneWidget);
    });
  });

  group('the favourites screen', () {
    Future<void> openFavourites(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.person_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your collection'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists what was hearted', (WidgetTester tester) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container(
        favourites: FavouritesMockDataSource(seed: <String>{'r1'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openFavourites(tester);

      expect(find.byType(FavouritesPage), findsOneWidget);
      expect(find.text('Paradise Biryani'), findsOneWidget);
    });

    testWidgets('says so when nothing is saved', (WidgetTester tester) async {
      _useTallSurface(tester);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await _settle(tester);
      await openFavourites(tester);

      expect(find.text('No favourites yet'), findsOneWidget);
      expect(find.text('Browse restaurants'), findsOneWidget);
    });
  });

  group('FavouritesController', () {
    test('toggling twice ends where it started, and saves nothing twice', () async {
      final FavouritesMockDataSource source = FavouritesMockDataSource();
      final ProviderContainer container = _container(favourites: source);
      addTearDown(container.dispose);

      await container.read(favouritesProvider.future);
      final List<Restaurant> feed = await container
          .read(restaurantRepositoryProvider)
          .getNearbyRestaurants();
      final Restaurant first = feed.first;

      final FavouritesController controller = container.read(
        favouritesProvider.notifier,
      );

      await controller.toggle(first);
      expect(controller.isFavourite(first.id), isTrue);

      // Idempotent at the source, exactly as the composite primary key makes it
      // in Postgres: hearting the same restaurant twice is one favourite.
      await controller.toggle(first);
      await controller.toggle(first);
      expect(await source.fetchFavourites(), hasLength(1));

      await controller.toggle(first);
      expect(controller.isFavourite(first.id), isFalse);
      expect(await source.fetchFavourites(), isEmpty);
    });

    test('a failed write throws so the UI can speak', () async {
      final ProviderContainer container = _container(
        favourites: _FailingFavourites(),
      );
      addTearDown(container.dispose);

      await container.read(favouritesProvider.future);
      final Restaurant first = (await container
              .read(restaurantRepositoryProvider)
              .getNearbyRestaurants())
          .first;

      await expectLater(
        container.read(favouritesProvider.notifier).toggle(first),
        throwsA(isA<FavouritesFailure>()),
      );
      expect(container.read(favouritesProvider).valueOrNull, isEmpty);
    });
  });
}
