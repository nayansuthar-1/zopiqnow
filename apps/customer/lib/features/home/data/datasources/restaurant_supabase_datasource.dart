import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The real catalog: `public.restaurants` over PostgREST.
///
/// Row-level security already restricts this to active restaurants, so the
/// queries below carry no `is_active` filter — a client-side filter would be
/// decoration, since a client cannot be trusted to apply one anyway.
class RestaurantSupabaseDataSource implements RestaurantDataSource {
  const RestaurantSupabaseDataSource();

  /// Resolved per call rather than injected: `Supabase.instance` only exists
  /// after `Supabase.initialize` in `main`, and widget tests never call it.
  SupabaseClient get _db => Supabase.instance.client;

  static const String _columns =
      'id, name, cuisines, rating, rating_count, eta_minutes, price_for_two, '
      'distance_km, is_veg, image_url, promo_text';

  @override
  Future<List<Restaurant>> fetchNearby() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurants')
        .select(_columns)
        // `ascending: true` is not decoration: postgrest-dart's `order()`
        // defaults to DESCENDING, so the bare call put the farthest restaurants
        // at the top of the feed. Every `order` in this app states its direction.
        .order('distance_km', ascending: true);
    return rows.map(_toRestaurant).toList(growable: false);
  }

  @override
  Future<Restaurant?> fetchById(String id) async {
    final Map<String, dynamic>? row = await _db
        .from('restaurants')
        .select(_columns)
        .eq('id', id)
        // Not `.single()`: that throws on no rows, and "no such restaurant" is
        // an answer, not a failure. The repository decides what it means.
        .maybeSingle();
    return row == null ? null : _toRestaurant(row);
  }

  @override
  Future<List<Restaurant>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <Restaurant>[];

    // Matches the generated `search_text` column, so a query hits both the name
    // and the cuisine tags. Ranking and typo tolerance belong to a real search
    // service; trigram `ilike` is honest enough until then.
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurants')
        .select(_columns)
        .ilike('search_text', '%$q%')
        .order('rating', ascending: false);
    return rows.map(_toRestaurant).toList(growable: false);
  }

  /// Postgres row → domain entity. Numeric columns arrive as `num` (int or
  /// double depending on the value), so every one is coerced explicitly.
  Restaurant _toRestaurant(Map<String, dynamic> row) => Restaurant(
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
}
