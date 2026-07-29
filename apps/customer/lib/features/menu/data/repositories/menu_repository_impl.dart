import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';

/// Default [MenuRepository]. Names the data source interface, so the mock and
/// Postgres are interchangeable.
class MenuRepositoryImpl implements MenuRepository {
  const MenuRepositoryImpl(this._dataSource);

  final MenuDataSource _dataSource;

  @override
  Future<List<MenuCategory>> getMenu(String restaurantId) async {
    try {
      return await _dataSource.fetchMenu(restaurantId);
    } on Object catch (_) {
      throw const MenuLoadFailure();
    }
  }

  @override
  Future<List<RestaurantReview>> getReviews(String restaurantId) async {
    try {
      return await _dataSource.fetchReviews(restaurantId);
    } on Object catch (_) {
      // Swallowed on purpose. The menu is the screen; the wall is a section of
      // it, and a restaurant page that goes red because one RPC hiccuped is a
      // restaurant nobody can order from.
      return const <RestaurantReview>[];
    }
  }
}
