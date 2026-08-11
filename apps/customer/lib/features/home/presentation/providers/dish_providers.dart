import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/home/data/datasources/dish_discovery_datasource.dart';
import 'package:zopiqnow/features/home/domain/dish_ranking.dart';
import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/search/presentation/providers/search_providers.dart';

final Provider<DishDiscoveryDataSource> dishDiscoveryDataSourceProvider =
    Provider<DishDiscoveryDataSource>(
      (Ref ref) => const DishDiscoveryDataSource(),
    );

/// Every dish we could recommend, already paired with its kitchen.
///
/// The join is against the nearby feed rather than a second restaurant query,
/// and that is not only a saved round trip: it is what makes the rail agree with
/// the rest of Home. A dish whose restaurant is not in the feed is one we are
/// not showing anywhere else on the screen, so it is dropped rather than
/// rendered as a card that names a kitchen the customer cannot find.
///
/// Not `autoDispose`, for the same reason [nearbyRestaurantsProvider] is not —
/// and it rides that provider's refresh for free: watching `.future` means Home's
/// pull-to-refresh invalidates the feed, which rebuilds this, which refetches the
/// dishes. There is nothing extra to remember to invalidate.
final FutureProvider<List<DishSuggestion>> dishPoolProvider =
    FutureProvider<List<DishSuggestion>>((Ref ref) async {
      final List<Restaurant> restaurants = await ref.watch(
        nearbyRestaurantsProvider.future,
      );
      final List<DishRow> rows = await ref
          .watch(dishDiscoveryDataSourceProvider)
          .fetchPool();
      return joinDishes(rows, restaurants);
    });

/// "Recommended for you" — dishes, ranked against what this phone has been
/// searching for.
///
/// The whole personalisation signal is [recentSearchesProvider], which is local
/// to the device and already persisted. Nothing here is sent anywhere, and a
/// customer who has never searched still gets a rail — quality and the daily
/// rotation carry it on their own.
final Provider<AsyncValue<List<DishSuggestion>>> recommendedDishesProvider =
    Provider<AsyncValue<List<DishSuggestion>>>((Ref ref) {
      final List<String> interests = ref.watch(recentSearchesProvider);
      final bool vegOnly = ref.watch(vegModeProvider);

      return ref.watch(dishPoolProvider).whenData((List<DishSuggestion> pool) {
        return diversify(
          rankDishes(
            pool: orderableDishes(pool, vegOnly: vegOnly),
            interests: interests,
            rotation: rotationForToday(),
          ),
          limit: _railLength,
        );
      });
    });

/// The same rail on a category page, narrowed to that category.
///
/// It ignores the chip row, exactly as the restaurant rail it replaces did, so
/// the section does not empty out while filters are being tried.
final ProviderFamily<AsyncValue<List<DishSuggestion>>, String>
categoryDishesProvider =
    Provider.family<AsyncValue<List<DishSuggestion>>, String>((
      Ref ref,
      String label,
    ) {
      final List<String> interests = ref.watch(recentSearchesProvider);
      final bool vegOnly = ref.watch(vegModeProvider);

      return ref.watch(dishPoolProvider).whenData((List<DishSuggestion> pool) {
        final List<DishSuggestion> inCategory =
            orderableDishes(pool, vegOnly: vegOnly)
                .where((DishSuggestion d) => _matchesCategory(d, label))
                .toList(growable: false);

        return diversify(
          rankDishes(
            pool: inCategory,
            interests: interests,
            rotation: rotationForToday(),
          ),
          limit: _railLength,
        );
      });
    });

/// The restaurants a category page lists.
///
/// A kitchen belongs to "Manchurian" when it *cooks* Manchurian — not only when
/// the word turns up in its name or cuisine tags. Tags were the whole test, and
/// on a real device it read as a contradiction: the rail at the top of the page
/// showed two Manchurian dishes from 9Tiz Cafe, and the list directly underneath
/// said "No Manchurian near you yet", because 9Tiz is tagged *Chinese*.
///
/// So the dish pool decides too. Still no round trip — the pool is already
/// loaded for the rail — so switching categories stays instant.
final ProviderFamily<AsyncValue<List<Restaurant>>, String>
categoryRestaurantsProvider =
    Provider.family<AsyncValue<List<Restaurant>>, String>((
      Ref ref,
      String label,
    ) {
      final HomeFilters filters = ref.watch(homeFiltersProvider);
      final HomeFilters effective = ref.watch(vegModeProvider)
          ? filters.copyWith(pureVeg: true)
          : filters;

      // `valueOrNull`: a pool that has not landed yet must not empty the list.
      // Tags alone still answer, and the dishes widen it when they arrive.
      final List<DishSuggestion> pool =
          ref.watch(dishPoolProvider).valueOrNull ?? const <DishSuggestion>[];

      final Set<String> cooking = <String>{
        for (final DishSuggestion d in pool)
          if (_matchesCategory(d, label)) d.restaurant.id,
      };

      return ref.watch(nearbyRestaurantsProvider).whenData((
        List<Restaurant> all,
      ) {
        final List<Restaurant> inCategory = all
            .where(
              (Restaurant r) =>
                  restaurantTagged(r, label) || cooking.contains(r.id),
            )
            .toList();
        return effective.apply(inCategory);
      });
    });

const int _railLength = 12;

/// A dish belongs to a category when the dish says so, its menu section says so,
/// or its kitchen's cuisine tags say so.
///
/// The last two are the same fields the restaurant-level category page matches
/// on, so a category page's rail and its list agree about what "Pizza" means.
bool _matchesCategory(DishSuggestion dish, String label) {
  final String needle = label.toLowerCase();
  return dish.item.name.toLowerCase().contains(needle) ||
      dish.category.toLowerCase().contains(needle) ||
      dish.restaurant.cuisines.any(
        (String c) => c.toLowerCase().contains(needle),
      );
}

/// Rows → suggestions, dropping any dish whose kitchen is not in [restaurants].
///
/// Shared with dish search, which joins the same way against the same feed.
List<DishSuggestion> joinDishes(
  List<DishRow> rows,
  List<Restaurant> restaurants,
) {
  final Map<String, Restaurant> byId = <String, Restaurant>{
    for (final Restaurant r in restaurants) r.id: r,
  };

  final List<DishSuggestion> joined = <DishSuggestion>[];
  for (final DishRow row in rows) {
    final Restaurant? restaurant = byId[row.restaurantId];
    if (restaurant == null) continue;
    joined.add(
      DishSuggestion(
        item: row.item,
        restaurant: restaurant,
        category: row.category,
      ),
    );
  }
  return joined;
}

/// Dishes a customer could actually order right now.
///
/// A paused kitchen's dish is left out of the *rail* rather than shown with a
/// dead ADD button. The rail is a suggestion, and suggesting something that
/// cannot be bought is worse than suggesting one thing fewer — so if every
/// kitchen is shut the rail simply hides, and the restaurant list below still
/// explains why. Search does not use this filter: a deliberate query deserves
/// its answer, closed or not.
///
/// Account's "100% Veg Mode" is a standing preference, so it filters
/// merchandising too — the same call [filteredRestaurantsProvider] makes.
List<DishSuggestion> orderableDishes(
  List<DishSuggestion> pool, {
  required bool vegOnly,
}) {
  return pool
      .where(
        (DishSuggestion d) =>
            d.restaurant.acceptingOrders && (!vegOnly || d.item.isVeg),
      )
      .toList(growable: false);
}

/// Days since the epoch — the rail's rotation seed.
///
/// Read once per provider build rather than per frame, which is what makes the
/// order hold still while somebody is scrolling. It moves at midnight, and the
/// next launch picks up the new arrangement.
int rotationForToday() =>
    DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
