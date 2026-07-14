import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// In-memory favourites — the tests' data source.
///
/// Resolves ids against the mock catalog, so a favourite is a real [Restaurant]
/// here exactly as it is a real one in Postgres. Storing whole entities instead
/// would let a test favourite a restaurant that does not exist, which Postgres
/// would refuse (the foreign key) and the UI would never survive.
class FavouritesMockDataSource implements FavouritesDataSource {
  FavouritesMockDataSource({
    this.latency = Duration.zero,
    Set<String>? seed,
  }) : _ids = <String>{...?seed};

  final Duration latency;

  /// Newest first is the contract, and insertion order is how a LinkedHashSet
  /// keeps it — reversed on read.
  final Set<String> _ids;

  static const RestaurantMockDataSource _catalog = RestaurantMockDataSource(
    latency: Duration.zero,
  );

  /// `Future.delayed(Duration.zero)` still *arms a Timer*, and a widget test that
  /// ends before it fires fails on "a Timer is still pending". Every restaurant
  /// card reads favourites, so that would be every Home test in the suite — for
  /// a delay of nothing. A zero latency therefore schedules nothing at all.
  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<List<Restaurant>> fetchFavourites() async {
    await _wait();
    final List<Restaurant> all = await _catalog.fetchNearby();
    return <Restaurant>[
      for (final String id in _ids.toList().reversed)
        ...all.where((Restaurant r) => r.id == id),
    ];
  }

  @override
  Future<void> addFavourite(String restaurantId) async {
    await _wait();
    _ids.add(restaurantId); // Idempotent, like the composite key it stands in for.
  }

  @override
  Future<void> removeFavourite(String restaurantId) async {
    await _wait();
    _ids.remove(restaurantId);
  }
}
