import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
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
}
