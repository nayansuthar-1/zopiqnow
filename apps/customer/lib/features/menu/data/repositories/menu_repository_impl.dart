import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';

/// Default [MenuRepository] over the mock data source.
class MenuRepositoryImpl implements MenuRepository {
  const MenuRepositoryImpl(this._dataSource);

  final MenuMockDataSource _dataSource;

  @override
  Future<List<MenuCategory>> getMenu(String restaurantId) async {
    try {
      return await _dataSource.fetchMenu(restaurantId);
    } on Object catch (_) {
      throw const MenuLoadFailure();
    }
  }
}
