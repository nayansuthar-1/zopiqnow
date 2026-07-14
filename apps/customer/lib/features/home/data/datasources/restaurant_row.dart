import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The `restaurants` columns every query selects, and the one place a row of
/// them becomes a [Restaurant].
///
/// Shared because favourites reads restaurants too — through a join, but the
/// same columns into the same entity. Two copies of this mapping would be two
/// places to forget `promo_text` the day someone adds a column.
const String restaurantColumns =
    'id, name, cuisines, rating, rating_count, eta_minutes, price_for_two, '
    'distance_km, is_veg, image_url, promo_text';

/// Postgres row → domain entity. Numeric columns arrive as `num` (int or double
/// depending on the value), so every one is coerced explicitly.
Restaurant restaurantFromRow(Map<String, dynamic> row) => Restaurant(
  id: row['id'] as String,
  name: row['name'] as String,
  cuisines: (row['cuisines'] as List<dynamic>).cast<String>(),
  rating: (row['rating'] as num).toDouble(),
  ratingCount: (row['rating_count'] as num).toInt(),
  etaMinutes: (row['eta_minutes'] as num).toInt(),
  priceForTwo: (row['price_for_two'] as num).toInt(),
  distanceKm: (row['distance_km'] as num).toDouble(),
  isVeg: row['is_veg'] as bool,
  imageUrl: row['image_url'] as String,
  promoText: row['promo_text'] as String?,
);
