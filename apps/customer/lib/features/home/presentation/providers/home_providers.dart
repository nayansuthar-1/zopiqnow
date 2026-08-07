import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/home/data/datasources/hero_slide_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/home_catalog_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_supabase_datasource.dart';
import 'package:zopiqnow/features/home/data/repositories/restaurant_repository_impl.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/hero_slide.dart';
import 'package:zopiqnow/features/home/domain/entities/offer.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// [RestaurantMockDataSource] to inject latency and failure without a network.
final Provider<RestaurantDataSource> restaurantDataSourceProvider =
    Provider<RestaurantDataSource>(
      (Ref ref) => const RestaurantSupabaseDataSource(),
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

/// The Home hero's campaign slides (migration 0053).
///
/// Not `autoDispose`, and that is the cache. Slides change when an admin
/// publishes one — perhaps weekly — so a fetch per Home build would be a
/// request per app resume for content that has not moved. Kept for the life of
/// the process and invalidated by Home's pull-to-refresh, which is the gesture
/// a person already makes when they expect the screen to be newer than it is.
final Provider<HeroSlideDataSource> heroSlideDataSourceProvider =
    Provider<HeroSlideDataSource>((Ref ref) => const HeroSlideDataSource());

final FutureProvider<List<HeroSlide>> heroSlidesProvider =
    FutureProvider<List<HeroSlide>>(
      (Ref ref) => ref.watch(heroSlideDataSourceProvider).fetchLive(),
    );

/// Merchandising content for the category rail and the offers carousel.
final Provider<HomeCatalogDataSource> homeCatalogDataSourceProvider =
    Provider<HomeCatalogDataSource>((Ref ref) => const HomeCatalogDataSource());

final Provider<List<FoodCategory>> foodCategoriesProvider =
    Provider<List<FoodCategory>>(
      (Ref ref) => ref.watch(homeCatalogDataSourceProvider).fetchCategories(),
    );

/// The "View More" sheet's dish list, with Account's "100% Veg Mode" applied.
///
/// Same rule as [filteredRestaurantsProvider]: the mode is a standing
/// preference, so it filters the merchandising too. Filtering here rather than
/// in the sheet keeps the toggle live — flipping veg mode rebuilds the grid
/// under an open sheet.
final Provider<List<FoodCategory>> moreFoodCategoriesProvider =
    Provider<List<FoodCategory>>((Ref ref) {
      final List<FoodCategory> all = ref
          .watch(homeCatalogDataSourceProvider)
          .fetchMoreCategories();

      return ref.watch(vegModeProvider)
          ? all
                .where((FoodCategory category) => category.isVeg)
                .toList(growable: false)
          : all;
    });

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

      // Account's "100% Veg Mode" forces the chip on and cannot be turned off
      // from here — that is what makes it a *mode* rather than a second copy of
      // the Pure Veg chip. One predicate does the filtering either way, so the
      // two controls can never disagree about what "veg" means.
      final HomeFilters effective = ref.watch(vegModeProvider)
          ? filters.copyWith(pureVeg: true)
          : filters;

      return ref
          .watch(nearbyRestaurantsProvider)
          .whenData((List<Restaurant> all) => effective.apply(all));
    });

/// Home's feed scroll position, owned here rather than by [HomePage].
///
/// The shell needs it: system Back on the Delivery tab returns the feed to the
/// top before it will leave the app, and the shell is the widget that hears
/// Back. A controller created inside `HomePage.initState` is unreachable from
/// there, and lifting it into a provider is cheaper than threading a callback
/// up through a route the shell does not own.
final Provider<ScrollController> homeScrollControllerProvider =
    Provider<ScrollController>((Ref ref) {
      final ScrollController controller = ScrollController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Restaurants serving one category, keyed by its label ("Pizza", "Biryani").
///
/// Filtered out of [nearbyRestaurantsProvider] rather than through
/// `searchRestaurants`, and the difference matters. The server search is an
/// `ilike` over `search_text`, which is name + cuisines — the same two fields
/// matched here — but it searches *every* restaurant on the platform, including
/// ones that do not deliver to this address. The nearby feed has already applied
/// the delivery radius, so filtering it keeps the promise the section header
/// makes: these are restaurants delivering to you.
///
/// It also costs no round trip, so switching categories is instant.
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

      return ref
          .watch(nearbyRestaurantsProvider)
          .whenData(
            (List<Restaurant> all) => effective.apply(_inCategory(all, label)),
          );
    });

/// The "Recommended for you" rail on a category page. Highest-rated in that
/// category, and — like [topRatedRestaurantsProvider], which it mirrors — it
/// ignores the chip row, so the rail does not empty out as filters are tried.
final ProviderFamily<AsyncValue<List<Restaurant>>, String>
categoryTopRatedProvider =
    Provider.family<AsyncValue<List<Restaurant>>, String>((
      Ref ref,
      String label,
    ) {
      return ref.watch(nearbyRestaurantsProvider).whenData((
        List<Restaurant> all,
      ) {
        final List<Restaurant> sorted = _inCategory(all, label)
          ..sort((Restaurant a, Restaurant b) => b.rating.compareTo(a.rating));
        return sorted.take(_topChainCount).toList(growable: false);
      });
    });

/// Name or cuisine tag contains the label. Deliberately the same two fields the
/// server's `search_text` column is generated from, so a category page and a
/// typed search for the same word agree with each other.
List<Restaurant> _inCategory(List<Restaurant> all, String label) {
  final String needle = label.toLowerCase();
  return all
      .where(
        (Restaurant r) =>
            r.name.toLowerCase().contains(needle) ||
            r.cuisines.any((String c) => c.toLowerCase().contains(needle)),
      )
      .toList();
}

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
