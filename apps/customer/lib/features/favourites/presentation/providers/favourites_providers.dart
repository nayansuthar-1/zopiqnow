import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/favourites/data/datasources/favourites_supabase_datasource.dart';
import 'package:zopiqnow/features/favourites/data/repositories/favourites_repository_impl.dart';
import 'package:zopiqnow/features/favourites/domain/repositories/favourites_repository.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// `FavouritesMockDataSource`.
final Provider<FavouritesDataSource> favouritesDataSourceProvider =
    Provider<FavouritesDataSource>(
      (Ref ref) => const FavouritesSupabaseDataSource(),
    );

final Provider<FavouritesRepository> favouritesRepositoryProvider =
    Provider<FavouritesRepository>(
      (Ref ref) => FavouritesRepositoryImpl(ref.watch(favouritesDataSourceProvider)),
    );

/// The customer's saved restaurants, and the only thing that writes them.
///
/// Not auto-disposed: the heart on every restaurant card reads this, so it is
/// live for as long as Home is, and re-fetching the whole list each time a card
/// scrolls into view would be absurd.
class FavouritesController extends AsyncNotifier<List<Restaurant>> {
  @override
  Future<List<Restaurant>> build() async {
    // Signing out must empty the list rather than leave the last account's
    // favourites hearted on screen.
    ref.watch(authControllerProvider);
    return ref.watch(favouritesRepositoryProvider).getFavourites();
  }

  bool isFavourite(String restaurantId) =>
      state.valueOrNull?.any((Restaurant r) => r.id == restaurantId) ?? false;

  /// Hearts or un-hearts [restaurant], **optimistically**.
  ///
  /// A heart that waits for a round trip before filling in feels broken — this
  /// is the cheapest, most-tapped interaction in the app, and it has to be
  /// instant. So the list changes first and the network follows; if the write
  /// fails, the change is put back exactly as it was and the failure is thrown
  /// for the caller to say out loud. An optimistic update that silently keeps a
  /// lie on screen is worse than a spinner.
  Future<void> toggle(Restaurant restaurant) async {
    final List<Restaurant> before = state.valueOrNull ?? const <Restaurant>[];
    final bool wasFavourite = isFavourite(restaurant.id);

    state = AsyncData<List<Restaurant>>(
      wasFavourite
          ? before.where((Restaurant r) => r.id != restaurant.id).toList()
          : <Restaurant>[restaurant, ...before],
    );

    try {
      final FavouritesRepository repository = ref.read(
        favouritesRepositoryProvider,
      );
      if (wasFavourite) {
        await repository.remove(restaurant.id);
      } else {
        await repository.add(restaurant.id);
      }
    } on FavouritesFailure {
      state = AsyncData<List<Restaurant>>(before);
      rethrow;
    }
  }
}

final AsyncNotifierProvider<FavouritesController, List<Restaurant>>
favouritesProvider =
    AsyncNotifierProvider<FavouritesController, List<Restaurant>>(
      FavouritesController.new,
    );

/// Whether one restaurant is hearted. A `select` on the list, so a card rebuilds
/// only when *its own* heart changes — not every time any restaurant is
/// favourited anywhere on the screen.
final ProviderFamily<bool, String> isFavouriteProvider =
    Provider.family<bool, String>(
      (Ref ref, String restaurantId) => ref.watch(
        favouritesProvider.select(
          (AsyncValue<List<Restaurant>> favourites) =>
              favourites.valueOrNull?.any(
                (Restaurant r) => r.id == restaurantId,
              ) ??
              false,
        ),
      ),
    );
