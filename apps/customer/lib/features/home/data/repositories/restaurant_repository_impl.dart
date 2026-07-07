import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';

/// Default [RestaurantRepository]. Today it reads the mock data source; the
/// only change to go live is swapping the injected data source for an HTTP one.
class RestaurantRepositoryImpl implements RestaurantRepository {
  const RestaurantRepositoryImpl(this._dataSource);

  final RestaurantMockDataSource _dataSource;

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
}
