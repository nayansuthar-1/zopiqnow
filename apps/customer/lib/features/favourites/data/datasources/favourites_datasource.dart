import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The favourites contract, implemented by the mock and by Supabase.
///
/// No user id, for the third time and the same reason: `auth.uid()` says whose
/// favourites these are, through the row-level policies on `favourites`.
abstract interface class FavouritesDataSource {
  /// The signed-in customer's favourites, newest first.
  Future<List<Restaurant>> fetchFavourites();

  /// Idempotent. Tapping the heart twice on a flaky network must not save two
  /// favourites, and a retried insert the client never saw succeed must not be
  /// an error — the composite primary key makes it a no-op instead.
  Future<void> addFavourite(String restaurantId);

  Future<void> removeFavourite(String restaurantId);
}
