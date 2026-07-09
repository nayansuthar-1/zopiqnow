import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/home/data/datasources/home_catalog_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/data/repositories/restaurant_repository_impl.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/offer.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';

/// Data source binding. Overridden in tests to inject latency/failure, and
/// later replaced by the HTTP data source.
final Provider<RestaurantMockDataSource> restaurantDataSourceProvider =
    Provider<RestaurantMockDataSource>(
      (Ref ref) => const RestaurantMockDataSource(),
    );

/// Repository binding — the seam the UI depends on (SAD 7.4).
final Provider<RestaurantRepository> restaurantRepositoryProvider =
    Provider<RestaurantRepository>(
      (Ref ref) =>
          RestaurantRepositoryImpl(ref.watch(restaurantDataSourceProvider)),
    );

/// The Home feed as an [AsyncValue]: loading → data | error, giving the UI its
/// shimmer/success/error states for free. Retry = `ref.invalidate(...)`.
final FutureProvider<List<Restaurant>> nearbyRestaurantsProvider =
    FutureProvider<List<Restaurant>>(
      (Ref ref) =>
          ref.watch(restaurantRepositoryProvider).getNearbyRestaurants(),
    );

/// A single restaurant, for the menu screen. A family so a cold deep link to
/// `/restaurant/:id` resolves without the Home feed ever having loaded.
final AutoDisposeFutureProviderFamily<Restaurant, String>
restaurantByIdProvider = FutureProvider.autoDispose.family<Restaurant, String>(
  (Ref ref, String id) =>
      ref.watch(restaurantRepositoryProvider).getRestaurantById(id),
);

/// Merchandising content for the category rail and the offers carousel.
final Provider<HomeCatalogDataSource> homeCatalogDataSourceProvider =
    Provider<HomeCatalogDataSource>((Ref ref) => const HomeCatalogDataSource());

final Provider<List<FoodCategory>> foodCategoriesProvider =
    Provider<List<FoodCategory>>(
      (Ref ref) => ref.watch(homeCatalogDataSourceProvider).fetchCategories(),
    );

final Provider<List<Offer>> offersProvider = Provider<List<Offer>>(
  (Ref ref) => ref.watch(homeCatalogDataSourceProvider).fetchOffers(),
);

/// Chip-row state (toggles + sort order).
final NotifierProvider<HomeFiltersNotifier, HomeFilters> homeFiltersProvider =
    NotifierProvider<HomeFiltersNotifier, HomeFilters>(HomeFiltersNotifier.new);

class HomeFiltersNotifier extends Notifier<HomeFilters> {
  @override
  HomeFilters build() => const HomeFilters();

  void toggleFastDelivery() =>
      state = state.copyWith(fastDelivery: !state.fastDelivery);

  void toggleRatingAbove4() =>
      state = state.copyWith(ratingAbove4: !state.ratingAbove4);

  void togglePureVeg() => state = state.copyWith(pureVeg: !state.pureVeg);

  void toggleGreatOffers() =>
      state = state.copyWith(greatOffers: !state.greatOffers);

  void setSort(HomeSort sort) => state = state.copyWith(sort: sort);
}

/// The feed with the chip row applied. Maps only the data case, so Home keeps
/// its shimmer and retry states untouched.
final Provider<AsyncValue<List<Restaurant>>> filteredRestaurantsProvider =
    Provider<AsyncValue<List<Restaurant>>>((Ref ref) {
      final HomeFilters filters = ref.watch(homeFiltersProvider);
      return ref
          .watch(nearbyRestaurantsProvider)
          .whenData((List<Restaurant> all) => filters.apply(all));
    });

/// "Top restaurant chains" rail — highest-rated first, ignores the chip row.
final Provider<AsyncValue<List<Restaurant>>> topRatedRestaurantsProvider =
    Provider<AsyncValue<List<Restaurant>>>((Ref ref) {
      return ref.watch(nearbyRestaurantsProvider).whenData((
        List<Restaurant> all,
      ) {
        final List<Restaurant> sorted = List<Restaurant>.of(all)
          ..sort((Restaurant a, Restaurant b) => b.rating.compareTo(a.rating));
        return sorted.take(_topChainCount).toList();
      });
    });

const int _topChainCount = 6;
