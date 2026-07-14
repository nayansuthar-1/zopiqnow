import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/favourites/domain/repositories/favourites_repository.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Default [FavouritesRepository]. Names the data source interface, so the mock
/// and Postgres are interchangeable.
class FavouritesRepositoryImpl implements FavouritesRepository {
  const FavouritesRepositoryImpl(this._dataSource);

  final FavouritesDataSource _dataSource;

  @override
  Future<List<Restaurant>> getFavourites() async {
    try {
      return await _dataSource.fetchFavourites();
    } on Object catch (_) {
      throw const FavouritesFailure('We couldn\'t load your favourites.');
    }
  }

  @override
  Future<void> add(String restaurantId) async {
    try {
      await _dataSource.addFavourite(restaurantId);
    } on Object catch (_) {
      throw const FavouritesFailure('We couldn\'t save that favourite.');
    }
  }

  @override
  Future<void> remove(String restaurantId) async {
    try {
      await _dataSource.removeFavourite(restaurantId);
    } on Object catch (_) {
      throw const FavouritesFailure('We couldn\'t remove that favourite.');
    }
  }
}
