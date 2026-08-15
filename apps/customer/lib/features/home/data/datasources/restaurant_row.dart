import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The `restaurants` columns every query selects, and the one place a row of
/// them becomes a [Restaurant].
///
/// Shared because favourites reads restaurants too — through a join, but the
/// same columns into the same entity. Two copies of this mapping would be two
/// places to forget `promo_text` the day someone adds a column.
/// `latitude`/`longitude` and **not** `distance_km`.
///
/// The column is still there and still says 0 for every restaurant onboarded
/// through the admin console — 0001 carried it as "a plain column rather than
/// pretending to be computed", and 0027 called it "a typed-in number pretending
/// to be computed". Reading it is what put "0.0 km" on the card of a kitchen in
/// the next town. The coordinates are the real fact; the distance is derived
/// from them and the delivery address, in `home_providers.dart`.
const String restaurantColumns =
    'id, name, cuisines, rating, rating_count, eta_minutes, price_for_two, '
    'latitude, longitude, service_area_id, is_veg, image_url, promo_text, '
    'accepting_orders, pause_reason';

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
  // Left null here on purpose: nothing in the data layer knows where the
  // customer is. The feed fills it in once it does.
  latitude: (row['latitude'] as num?)?.toDouble(),
  longitude: (row['longitude'] as num?)?.toDouble(),
  // The town, computed from those coordinates by Postgres (0126). Read rather
  // than derived here so the app and the trigger that refuses cross-town orders
  // can never disagree about where a kitchen is.
  serviceAreaId: row['service_area_id'] as String?,
  isVeg: row['is_veg'] as bool,
  imageUrl: row['image_url'] as String,
  promoText: row['promo_text'] as String?,
  // A row written before the column existed reads null; treat it as open, the
  // same default the column carries.
  acceptingOrders: row['accepting_orders'] as bool? ?? true,
  pauseReason: row['pause_reason'] as String? ?? '',
);
