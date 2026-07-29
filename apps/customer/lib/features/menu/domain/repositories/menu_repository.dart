import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';

/// Contract for reading a restaurant's menu (SAD 7.4).
abstract interface class MenuRepository {
  /// The categorized menu for [restaurantId].
  ///
  /// Throws [MenuLoadFailure] on any transport/parse error.
  Future<List<MenuCategory>> getMenu(String restaurantId);

  /// The public review wall. Never throws — a restaurant page whose menu loaded
  /// is a working page, and failing it over the reviews would be trading the
  /// screen for a section. Empty on failure, which is also what a restaurant
  /// nobody has reviewed answers.
  Future<List<RestaurantReview>> getReviews(String restaurantId);
}

/// Domain-level failure for menu loading.
class MenuLoadFailure implements Exception {
  const MenuLoadFailure([this.message = 'We couldn\'t load this menu.']);

  final String message;

  @override
  String toString() => 'MenuLoadFailure: $message';
}
