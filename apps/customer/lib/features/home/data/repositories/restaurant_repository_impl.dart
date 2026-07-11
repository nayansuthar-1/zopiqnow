import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';

/// Default [RestaurantRepository]. It names the data source *interface*, which
/// is why going live meant changing one provider binding and nothing else.
class RestaurantRepositoryImpl implements RestaurantRepository {
  const RestaurantRepositoryImpl(this._dataSource);

  final RestaurantDataSource _dataSource;

  @override
  Future<List<Restaurant>> getNearbyRestaurants() async {
    try {
      return await _dataSource.fetchNearby();
    } on Object catch (_) {
      // Translate any transport/parse error into a domain failure so the UI
      // never sees infrastructure exceptions (SAD 7.7).
      throw const RestaurantLoadFailure();
    }
  }

  @override
  Future<Restaurant> getRestaurantById(String id) async {
    final Restaurant? found;
    try {
      found = await _dataSource.fetchById(id);
    } on Object catch (_) {
      throw const RestaurantLoadFailure();
    }
    // Thrown outside the try: a missing restaurant is a domain outcome, and
    // must not be caught and relabelled as a transport failure.
    if (found == null) throw const RestaurantNotFound();
    return found;
  }

  @override
  Future<List<Restaurant>> searchRestaurants(String query) async {
    try {
      return await _dataSource.search(query);
    } on Object catch (_) {
      throw const RestaurantLoadFailure('We couldn\'t run that search.');
    }
  }
}
