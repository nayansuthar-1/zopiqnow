import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';

/// The menu read contract, implemented by the mock and by Supabase.
abstract interface class MenuDataSource {
  /// The categorized menu for [restaurantId], in the vendor's own order.
  Future<List<MenuCategory>> fetchMenu(String restaurantId);
}
