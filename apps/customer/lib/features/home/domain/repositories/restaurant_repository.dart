import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Contract for reading restaurant discovery data. The presentation layer
/// depends only on this abstraction; the concrete implementation (mock today,
/// HTTP tomorrow) is bound via Riverpod (SAD 7.3 / 7.4).
abstract interface class RestaurantRepository {
  /// Restaurants serviceable near the user, ranked for discovery.
  ///
  /// Throws [RestaurantLoadFailure] on any transport/parse error so the
  /// presentation layer can surface a retryable error state.
  Future<List<Restaurant>> getNearbyRestaurants();

  /// A single restaurant by id, for the menu screen.
  ///
  /// Deliberately a fetch rather than a lookup in the loaded feed: the menu
  /// screen has to survive a cold deep link, when no feed has ever loaded.
  ///
  /// Throws [RestaurantNotFound] when no such restaurant exists, and
  /// [RestaurantLoadFailure] on any transport/parse error.
  Future<Restaurant> getRestaurantById(String id);
}

/// The requested restaurant does not exist — a stale link, or a vendor that has
/// since left the platform. Distinct from [RestaurantLoadFailure] because
/// retrying will never help.
class RestaurantNotFound implements Exception {
  const RestaurantNotFound([
    this.message = 'This restaurant is no longer available.',
  ]);

  final String message;

  @override
  String toString() => 'RestaurantNotFound: $message';
}

/// Domain-level failure for the Home feed. Keeps Flutter/HTTP details out of
/// the UI, which only needs a human message + the fact that it is retryable.
class RestaurantLoadFailure implements Exception {
  const RestaurantLoadFailure([
    this.message = 'We couldn\'t load restaurants near you.',
  ]);

  final String message;

  @override
  String toString() => 'RestaurantLoadFailure: $message';
}
