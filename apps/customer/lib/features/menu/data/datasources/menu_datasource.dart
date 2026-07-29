import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';

/// The menu read contract, implemented by the mock and by Supabase.
abstract interface class MenuDataSource {
  /// The categorized menu for [restaurantId], in the vendor's own order.
  Future<List<MenuCategory>> fetchMenu(String restaurantId);

  /// The public review wall, newest first (migration 0062).
  ///
  /// Open to a signed-out browser too: reading a restaurant does not require an
  /// account, and the reviews are the most useful thing on the page.
  Future<List<RestaurantReview>> fetchReviews(String restaurantId);
}
