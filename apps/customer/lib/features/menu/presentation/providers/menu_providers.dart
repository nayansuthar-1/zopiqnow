import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_supabase_datasource.dart';
import 'package:zopiqnow/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// [MenuMockDataSource].
final Provider<MenuDataSource> menuDataSourceProvider = Provider<MenuDataSource>(
  (Ref ref) => const MenuSupabaseDataSource(),
);

final Provider<MenuRepository> menuRepositoryProvider =
    Provider<MenuRepository>(
      (Ref ref) => MenuRepositoryImpl(ref.watch(menuDataSourceProvider)),
    );

/// Menu for a given restaurant id, as an [AsyncValue] (loading/data/error).
final AutoDisposeFutureProviderFamily<List<MenuCategory>, String> menuProvider =
    FutureProvider.autoDispose.family<List<MenuCategory>, String>(
      (Ref ref, String restaurantId) =>
          ref.watch(menuRepositoryProvider).getMenu(restaurantId),
    );

/// The restaurant's public review wall, newest first (migration 0062).
///
/// Never in an error state — the repository swallows to an empty list, which is
/// also what a restaurant nobody has reviewed answers. Both render as no
/// section, which is the honest outcome either way.
final AutoDisposeFutureProviderFamily<List<RestaurantReview>, String>
restaurantReviewsProvider =
    FutureProvider.autoDispose.family<List<RestaurantReview>, String>(
      (Ref ref, String restaurantId) =>
          ref.watch(menuRepositoryProvider).getReviews(restaurantId),
    );

/// The menu screen's "Veg only" switch.
///
/// Not `autoDispose`, unlike the two filters below, and the difference is the
/// point: this one is a dietary preference and survives to the next restaurant,
/// because somebody who eats vegetarian at one kitchen eats vegetarian at the
/// next. "Bestsellers" and a search term are about *this* menu and would be
/// nonsense carried to another.
final NotifierProvider<VegOnlyNotifier, bool> vegOnlyProvider =
    NotifierProvider<VegOnlyNotifier, bool>(VegOnlyNotifier.new);

class VegOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Show only what the kitchen marked a bestseller.
final AutoDisposeStateProvider<bool> bestsellersOnlyProvider =
    StateProvider.autoDispose<bool>((Ref ref) => false);

/// What the customer typed into the menu's search field. Empty means no search.
final AutoDisposeStateProvider<String> menuSearchProvider =
    StateProvider.autoDispose<String>((Ref ref) => '');

/// One section, chosen from the floating Menu button. Null is the whole menu.
///
/// **Shown alone rather than scrolled to**, which is the one place this departs
/// from the app it is modelled on. Scrolling to a section means measuring where
/// it starts, and in a lazily-built list the section somebody picked is usually
/// the one that has not been built yet — so the jump lands short, or nowhere, on
/// exactly the long menus that need it. Filtering to it is reliable, and it
/// answers the same question: the customer picked Desserts because they want to
/// look at desserts.
final AutoDisposeStateProvider<String?> focusedCategoryProvider =
    StateProvider.autoDispose<String?>((Ref ref) => null);

/// The offers this restaurant is running (migration 0064).
///
/// A family, unlike checkout's `offersProvider`, which is keyed off whatever is
/// in the cart — on a menu the customer is *reading*, the cart may hold another
/// restaurant's food or nothing at all.
///
/// Empty on failure. A missing offer strip is a smaller problem than a menu that
/// will not open, and the codes are honoured by the order service either way.
final AutoDisposeFutureProviderFamily<List<RestaurantOffer>, String>
restaurantOffersProvider =
    FutureProvider.autoDispose.family<List<RestaurantOffer>, String>((
      Ref ref,
      String restaurantId,
    ) async {
      try {
        return await ref.watch(orderRepositoryProvider).getOffers(restaurantId);
      } on Object {
        return const <RestaurantOffer>[];
      }
    });

/// The menu with the screen's filters applied, dropping categories that end up
/// empty so it never renders a heading over nothing.
///
/// Search matches a dish's name **or** its description, because "cheese" is a
/// thing somebody looks for and half the dishes that have it do not say so in
/// their name.
final AutoDisposeFutureProviderFamily<List<MenuCategory>, String>
filteredMenuProvider = FutureProvider.autoDispose
    .family<List<MenuCategory>, String>((Ref ref, String restaurantId) async {
      final List<MenuCategory> menu = await ref.watch(
        menuProvider(restaurantId).future,
      );

      final bool vegOnly = ref.watch(vegOnlyProvider);
      final bool bestsellersOnly = ref.watch(bestsellersOnlyProvider);
      final String query = ref.watch(menuSearchProvider).trim().toLowerCase();
      final String? focused = ref.watch(focusedCategoryProvider);
      if (!vegOnly && !bestsellersOnly && query.isEmpty && focused == null) {
        return menu;
      }

      bool keep(MenuItem i) =>
          (!vegOnly || i.isVeg) &&
          (!bestsellersOnly || i.isBestseller) &&
          (query.isEmpty ||
              i.name.toLowerCase().contains(query) ||
              i.description.toLowerCase().contains(query));

      final List<MenuCategory> result = <MenuCategory>[];
      for (final MenuCategory c in menu) {
        if (focused != null && c.title != focused) continue;
        final List<MenuItem> kept = c.items.where(keep).toList(growable: false);
        if (kept.isNotEmpty) {
          result.add(MenuCategory(title: c.title, items: kept));
        }
      }
      return result;
    });
