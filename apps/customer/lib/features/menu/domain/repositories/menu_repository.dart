import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';

/// Contract for reading a restaurant's menu (SAD 7.4).
abstract interface class MenuRepository {
  /// The categorized menu for [restaurantId].
  ///
  /// Throws [MenuLoadFailure] on any transport/parse error.
  Future<List<MenuCategory>> getMenu(String restaurantId);
}

/// Domain-level failure for menu loading.
class MenuLoadFailure implements Exception {
  const MenuLoadFailure([this.message = 'We couldn\'t load this menu.']);

  final String message;

  @override
  String toString() => 'MenuLoadFailure: $message';
}
