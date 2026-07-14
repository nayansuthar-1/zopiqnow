import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The customer's saved restaurants.
///
/// Account state, not device state — unlike the selected address or the recent
/// searches, a favourite is a thing about *you*, and it should follow you to a
/// new phone.
abstract interface class FavouritesRepository {
  /// Newest first. Empty when signed out: having no account and having no
  /// favourites look the same from here, and neither is an error.
  ///
  /// Throws [FavouritesFailure] on a transport error.
  Future<List<Restaurant>> getFavourites();

  Future<void> add(String restaurantId);

  Future<void> remove(String restaurantId);
}

/// Domain-level failure for reading or writing favourites.
class FavouritesFailure implements Exception {
  const FavouritesFailure([
    this.message = 'We couldn\'t update your favourites. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'FavouritesFailure: $message';
}
