import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/home/data/datasources/dish_discovery_datasource.dart';
import 'package:zopiqnow/features/home/domain/category_matching.dart';
import 'package:zopiqnow/features/home/domain/dish_ranking.dart';
import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
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

/// Whether the customer has asked for vegetarian food, by *either* of the two
/// ways this app offers to ask.
///
/// There are two, and the rails only knew about one. Account's "100% Veg Mode"
/// is a standing preference and was honoured; the **VEG MODE** switch in the
/// home app bar and the "Pure Veg" chip beside it both write
/// [HomeFilters.pureVeg], and that never reached the dish rails at all — so
/// turning on the most prominent veg control in the app filtered the restaurant
/// list underneath while "Recommended for you" carried on suggesting chicken.
///
/// The chip row is otherwise deliberately ignored here, so the rail does not
/// empty out while filters are being tried. Veg is not one of those: "fast
/// delivery" is a preference about browsing and this is a line somebody does not
/// cross. Watched through `select` so the rail still rebuilds only when the veg
/// answer changes, not on every unrelated chip.
final Provider<bool> _vegOnlyProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(vegModeProvider) ||
      ref.watch(homeFiltersProvider.select((HomeFilters f) => f.pureVeg)),
);

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
      final bool vegOnly = ref.watch(_vegOnlyProvider);

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

/// Every dish on the platform that belongs to one category tile.
///
/// Its own query, rather than a slice of [dishPoolProvider]. That pool is 200 of
/// 703 dishes chosen by an ordering the data cannot fill — no dish is rated and
/// only 42 are bestsellers — so entire kitchens were missing from it, and with
/// them every dosa on the platform. Tapping Dosa found nothing while Shiv Fast
/// Food was three streets away serving three of them.
///
/// `autoDispose`, unlike the recommendation pool: this is one category's answer
/// and it stops being interesting the moment the page is left. Switching tiles
/// on the page refetches, which is one small request and the reason the list can
/// be complete rather than a shortlist.
final AutoDisposeFutureProviderFamily<List<DishSuggestion>, FoodCategory>
categoryDishPoolProvider =
    FutureProvider.autoDispose.family<List<DishSuggestion>, FoodCategory>((
      Ref ref,
      FoodCategory category,
    ) async {
      final List<Restaurant> restaurants = await ref.watch(
        nearbyRestaurantsProvider.future,
      );
      final List<DishRow> rows = await ref
          .watch(dishDiscoveryDataSourceProvider)
          .fetchCategory(
            categoryTerms(category).map(categoryNeedle).toList(growable: false),
          );

      // The unfiltered tile list, not the veg-filtered one the rail draws: which
      // dish a name belongs to is a fact about the menu, and it must not change
      // shape when somebody turns veg mode on.
      return dishesInCategory(
        joinDishes(rows, restaurants),
        category,
        ref.watch(allFoodCategoriesProvider),
      );
    });

/// The same rail on a category page, narrowed to that category.
///
/// It ignores the chip row, exactly as the restaurant rail it replaces did, so
/// the section does not empty out while filters are being tried.
final AutoDisposeProviderFamily<AsyncValue<List<DishSuggestion>>, FoodCategory>
categoryDishesProvider =
    Provider.autoDispose.family<AsyncValue<List<DishSuggestion>>, FoodCategory>((
      Ref ref,
      FoodCategory category,
    ) {
      final List<String> interests = ref.watch(recentSearchesProvider);
      final bool vegOnly = ref.watch(_vegOnlyProvider);

      return ref
          .watch(categoryDishPoolProvider(category))
          .whenData(
            (List<DishSuggestion> pool) => diversify(
              rankDishes(
                pool: orderableDishes(pool, vegOnly: vegOnly),
                interests: interests,
                rotation: rotationForToday(),
              ),
              limit: _railLength,
            ),
          );
    });

/// The restaurants a category page lists, before the chip row.
///
/// A kitchen belongs to "Manchurian" when it *cooks* Manchurian — not when the
/// word turns up in its cuisine tags. Tags were the whole test once, and it read
/// as a contradiction on a real device: the rail showed two Manchurian dishes
/// from 9Tiz Cafe and the list underneath said "No Manchurian near you yet",
/// because 9Tiz is tagged *Chinese*. Then tags were added *beside* the dishes,
/// and the contradiction ran the other way — Sadri Restaurent tags itself
/// *Burgers*, so the Burger page listed a kitchen whose entire menu is Dal Fry
/// and Jeera Rice.
///
/// So for a dish tile the menu decides, alone. A cuisine tile is the one place
/// tags still answer: "North Indian" is a claim a kitchen makes about itself,
/// and no dish is going to be named after it.
final AutoDisposeFutureProviderFamily<List<Restaurant>, FoodCategory>
_categoryFeedProvider =
    FutureProvider.autoDispose.family<List<Restaurant>, FoodCategory>((
      Ref ref,
      FoodCategory category,
    ) async {
      final List<Restaurant> all = await ref.watch(
        nearbyRestaurantsProvider.future,
      );
      final List<DishSuggestion> pool = await ref.watch(
        categoryDishPoolProvider(category).future,
      );

      // Built from the whole category pool rather than the orderable one: a
      // kitchen that is shut still belongs on the list, with its card closed.
      final Set<String> cooking = <String>{
        for (final DishSuggestion d in pool) d.restaurant.id,
      };

      return all
          .where(
            (Restaurant r) =>
                cooking.contains(r.id) ||
                (category.kind == FoodCategoryKind.cuisine &&
                    restaurantTagged(r, category.label)),
          )
          .toList();
    });

/// [_categoryFeedProvider] with the chip row and veg mode applied.
///
/// Split in two so toggling a chip re-filters what is already loaded instead of
/// dropping the page back to a shimmer — the same shape [filteredRestaurantsProvider]
/// uses on Home.
final AutoDisposeProviderFamily<AsyncValue<List<Restaurant>>, FoodCategory>
categoryRestaurantsProvider =
    Provider.autoDispose.family<AsyncValue<List<Restaurant>>, FoodCategory>((
      Ref ref,
      FoodCategory category,
    ) {
      final HomeFilters filters = ref.watch(homeFiltersProvider);
      final HomeFilters effective = ref.watch(vegModeProvider)
          ? filters.copyWith(pureVeg: true)
          : filters;

      return ref.watch(_categoryFeedProvider(category)).whenData(effective.apply);
    });

const int _railLength = 12;

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
