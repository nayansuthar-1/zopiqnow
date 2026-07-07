import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/data/repositories/restaurant_repository_impl.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';

/// Data source binding. Overridden in tests to inject latency/failure, and
/// later replaced by the HTTP data source.
final Provider<RestaurantMockDataSource> restaurantDataSourceProvider =
    Provider<RestaurantMockDataSource>(
  (Ref ref) => const RestaurantMockDataSource(),
);

/// Repository binding — the seam the UI depends on (SAD 7.4).
final Provider<RestaurantRepository> restaurantRepositoryProvider =
    Provider<RestaurantRepository>(
  (Ref ref) => RestaurantRepositoryImpl(ref.watch(restaurantDataSourceProvider)),
);

/// The Home feed as an [AsyncValue]: loading → data | error, giving the UI its
/// shimmer/success/error states for free. Retry = `ref.invalidate(...)`.
final FutureProvider<List<Restaurant>> nearbyRestaurantsProvider =
    FutureProvider<List<Restaurant>>(
  (Ref ref) => ref.watch(restaurantRepositoryProvider).getNearbyRestaurants(),
);
