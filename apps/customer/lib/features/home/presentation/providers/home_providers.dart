import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/home/data/datasources/dish_popularity_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/hero_slide_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/home_catalog_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_photos_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_supabase_datasource.dart';
import 'package:zopiqnow/features/home/data/repositories/restaurant_repository_impl.dart';
import 'package:zopiqnow/features/home/domain/category_popularity.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/geo_distance.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
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
///
/// Distances are measured here rather than read from the database — see
/// [measureFrom] — and the feed is ordered by the result, which is what the
/// `order by distance_km` in the data source used to be doing with a column
/// that was 0 for every real restaurant.
///
/// Watching the address means changing it refetches. That is the right cost:
/// the delivery radius (0098) is a function of where you are, so a new address
/// deserves a fresh feed rather than the old one re-sorted — and since 0126 the
/// *town* is too, so switching from a Falna address to a Sadri one exchanges the
/// whole catalogue rather than re-sorting it.
///
/// **No town, no feed.** An unknown town yields an empty list rather than every
/// kitchen on the platform: showing a Sadri customer a Falna restaurant they
/// cannot order from is the failure this exists to prevent, and it must not be
/// what happens by default. Home tells them to set a location — see
/// [HomeNoLocationView] — which is a screen they can act on, unlike a list of
/// food from the wrong town.
final FutureProvider<List<Restaurant>> nearbyRestaurantsProvider =
    FutureProvider<List<Restaurant>>((Ref ref) async {
      final Address? from = ref.watch(selectedAddressProvider);
      final String? areaId = ref.watch(currentAreaIdProvider);
      if (areaId == null) return const <Restaurant>[];

      final List<Restaurant> all = await ref
          .watch(restaurantRepositoryProvider)
          .getNearbyRestaurants(areaId: areaId);

      final List<Restaurant> measured = measureFrom(all, from);
      // Nearest first, with the unmeasurable ones last rather than first — a
      // restaurant we cannot place is not a restaurant next door.
      measured.sort((Restaurant a, Restaurant b) {
        final double x = a.distanceKm ?? double.infinity;
        final double y = b.distanceKm ?? double.infinity;
        return x.compareTo(y);
      });
      return measured;
    });

final Provider<RestaurantPhotosDataSource> restaurantPhotosDataSourceProvider =
    Provider<RestaurantPhotosDataSource>(
      (Ref ref) => const RestaurantPhotosDataSource(),
    );

/// Dish photographs for the card strip, keyed by restaurant id (0119).
///
/// **A plain [Provider] over a map, not an [AsyncValue].** The card is complete
/// without these — it has the restaurant's own cover and a branded gradient
/// behind that — so there is no loading state worth showing and, more
/// importantly, no error state worth showing. A failed photo request must not be
/// able to put an error screen in front of a feed that loaded perfectly well, so
/// the async value is flattened here and anything that is not data reads as "no
/// extra photos yet".
///
/// Deliberately **not** keyed to the feed. Watching [nearbyRestaurantsProvider]
/// would make a card's photos wait on a distance sort they have nothing to do
/// with, and the request is bounded by the platform rather than by what is on
/// screen — so it runs on its own and the cards pick up their strips whenever it
/// lands, one rebuild later.
final FutureProvider<Map<String, List<String>>> restaurantCardPhotosProvider =
    FutureProvider<Map<String, List<String>>>(
      (Ref ref) => ref.watch(restaurantPhotosDataSourceProvider).fetch(),
    );

/// The map above, flattened. This is what widgets watch.
final Provider<Map<String, List<String>>> cardPhotosProvider =
    Provider<Map<String, List<String>>>(
      (Ref ref) => ref
          .watch(restaurantCardPhotosProvider)
          .maybeWhen(
            data: (Map<String, List<String>> photos) => photos,
            orElse: () => const <String, List<String>>{},
          ),
    );

/// A single restaurant, for the menu screen. A family so a cold deep link to
/// `/restaurant/:id` resolves without the Home feed ever having loaded — which
/// is why it measures its own distance instead of borrowing the feed's.
final AutoDisposeFutureProviderFamily<Restaurant, String>
restaurantByIdProvider = FutureProvider.autoDispose.family<Restaurant, String>((
  Ref ref,
  String id,
) async {
  final Address? from = ref.watch(selectedAddressProvider);
  final Restaurant restaurant = await ref
      .watch(restaurantRepositoryProvider)
      .getRestaurantById(id);
  return restaurant.withDistance(_kmFrom(from, restaurant));
});

/// Fills in [Restaurant.distanceKm] for a whole feed, from [from].
///
/// Null address, or a restaurant nobody has placed on the map, leaves the
/// distance null and the UI says nothing — the one thing it must not do is
/// print 0.0 km, which is what reading `restaurants.distance_km` did.
List<Restaurant> measureFrom(List<Restaurant> all, Address? from) => all
    .map((Restaurant r) => r.withDistance(_kmFrom(from, r)))
    .toList(growable: true);

/// Measured if we can, otherwise whatever the data source already knew.
///
/// The fallback is not the Postgres column — that is no longer read. It is for
/// sources that carry a distance of their own, which today means
/// `RestaurantMockDataSource` and its fixtures.
double? _kmFrom(Address? from, Restaurant r) =>
    distanceKmBetween(
      fromLat: from?.latitude,
      fromLng: from?.longitude,
      toLat: r.latitude,
      toLng: r.longitude,
    ) ??
    r.distanceKm;

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

final Provider<DishPopularityDataSource> dishPopularityDataSourceProvider =
    Provider<DishPopularityDataSource>(
      (Ref ref) => const DishPopularityDataSource(),
    );

/// Units sold per dish over the last quarter (migration 0145), for the tiles to
/// sort by.
///
/// Not `autoDispose`: it is one small aggregate read that every home rebuild and
/// every "View More" sheet wants, and re-fetching it each time the rail scrolls
/// out of view would be a request per glance.
final FutureProvider<List<DishOrderCount>> dishOrderCountsProvider =
    FutureProvider<List<DishOrderCount>>(
      (Ref ref) => ref.watch(dishPopularityDataSourceProvider).fetchCounts(),
    );

/// The category rail, most-ordered food first.
///
/// `valueOrNull ?? const []` rather than an `AsyncValue`, so the tiles render in
/// their shipped order on the first frame and settle into the popular order when
/// the counts land. The alternative is a shimmering rail on every cold start, to
/// decide the order of tiles the customer can already see — a spinner in front of
/// content that is ready is a worse answer than content in a slightly different
/// order for one frame.
final Provider<List<FoodCategory>> foodCategoriesProvider =
    Provider<List<FoodCategory>>((Ref ref) {
      final List<FoodCategory> shipped = ref
          .watch(homeCatalogDataSourceProvider)
          .fetchCategories();

      return orderByPopularity(
        categories: shipped,
        counts: ref.watch(dishOrderCountsProvider).valueOrNull ??
            const <DishOrderCount>[],
        vocabulary: ref.watch(allFoodCategoriesProvider),
      );
    });

/// Every tile the app ships, both rails, unfiltered and without "View More".
///
/// Not for display — this is the *vocabulary* `dishMatchesCategory` resolves
/// against when it asks whether a dish's name already names some other food. It
/// must stay complete: veg-filter it and a Lassi in the Shakes section stops
/// being claimed by the Lassi tile the moment somebody turns meat off, and the
/// Shake page silently changes what it means.
final Provider<List<FoodCategory>> allFoodCategoriesProvider =
    Provider<List<FoodCategory>>((Ref ref) {
      final HomeCatalogDataSource catalog = ref.watch(
        homeCatalogDataSourceProvider,
      );
      return <FoodCategory>[
        ...catalog.fetchCategories(),
        ...catalog.fetchMoreCategories(),
      ]..removeWhere((FoodCategory c) => c.id == 'view_more');
    });

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

      final List<FoodCategory> visible = ref.watch(vegModeProvider)
          ? all
                .where((FoodCategory category) => category.isVeg)
                .toList(growable: false)
          : all;

      // Sorted by the same rule as the rail. The sheet is the rest of the same
      // list, and two orders for one vocabulary would mean Pizza leading the
      // rail while the sheet still opened on whatever was written first.
      return orderByPopularity(
        categories: visible,
        counts: ref.watch(dishOrderCountsProvider).valueOrNull ??
            const <DishOrderCount>[],
        vocabulary: ref.watch(allFoodCategoriesProvider),
      );
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

/// Name or cuisine tag contains the label. Deliberately the same two fields the
/// server's `search_text` column is generated from, so a category page and a
/// typed search for the same word agree with each other.
///
/// Only cuisine tiles read this now. A *dish* tile asks the menu instead — a
/// kitchen that tags itself "Burgers" and cooks none is not on the Burger page.
/// See `categoryRestaurantsProvider` in `dish_providers.dart`.
bool restaurantTagged(Restaurant r, String label) {
  final String needle = label.toLowerCase();
  return r.name.toLowerCase().contains(needle) ||
      r.cuisines.any((String c) => c.toLowerCase().contains(needle));
}
