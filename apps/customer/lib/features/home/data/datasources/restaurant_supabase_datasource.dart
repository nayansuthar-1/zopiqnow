import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/core/storage/json_disk_cache.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_row.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The real catalog: `public.restaurants` over PostgREST.
///
/// Row-level security already restricts this to active restaurants, so the
/// queries below carry no `is_active` filter — a client-side filter would be
/// decoration, since a client cannot be trusted to apply one anyway.
///
/// The `service_area_id` filter on the two list reads is the other kind of
/// filter, and the distinction is worth keeping straight. It is **discovery, not
/// security**: it decides which town's kitchens a customer is shown, and a
/// client that dropped it would see the next town's restaurants and still be
/// unable to order from one. What makes the town lock real is
/// `orders_within_service_area` (0126), which refuses a cross-town order at the
/// table no matter who is asking.
class RestaurantSupabaseDataSource implements RestaurantDataSource {
  const RestaurantSupabaseDataSource();

  /// Resolved per call rather than injected: `Supabase.instance` only exists
  /// after `Supabase.initialize` in `main`, and widget tests never call it.
  SupabaseClient get _db => Supabase.instance.client;

  /// Cached to disk: this is the first screen, and on a slow or dead connection
  /// it is the difference between the app opening with the catalogue and the app
  /// opening with a spinner. Five minutes is well inside how often a kitchen
  /// opens or closes, and a vendor pausing orders reaches the card through the
  /// live `accepting_orders` column on the next refresh either way.
  @override
  Future<List<Restaurant>> fetchNearby({required String areaId}) async {
    final List<Map<String, dynamic>> rows = await JsonDiskCache.rows(
      // Keyed by town, or a customer who switches from a Falna address to a
      // Sadri one is served Falna's kitchens from disk for the next five
      // minutes — the exact thing the filter below exists to stop.
      key: 'restaurants_nearby_$areaId',
      fetch: () async => _db
          .from('restaurants')
          .select(restaurantColumns)
          .eq('service_area_id', areaId)
          // `ascending: true` is not decoration: postgrest-dart's `order()`
          // defaults to DESCENDING, so the bare call put the farthest
          // restaurants at the top of the feed. Every `order` in this app
          // states its direction.
          .order('distance_km', ascending: true),
    );
    return rows.map(restaurantFromRow).toList(growable: false);
  }

  @override
  Future<Restaurant?> fetchById(String id) async {
    final Map<String, dynamic>? row = await _db
        .from('restaurants')
        .select(restaurantColumns)
        .eq('id', id)
        // Not `.single()`: that throws on no rows, and "no such restaurant" is
        // an answer, not a failure. The repository decides what it means.
        .maybeSingle();
    return row == null ? null : restaurantFromRow(row);
  }

  @override
  Future<List<Restaurant>> search(String query, {required String areaId}) async {
    final String q = query.trim();
    if (q.isEmpty) return const <Restaurant>[];

    // Matches the generated `search_text` column, so a query hits both the name
    // and the cuisine tags. Ranking and typo tolerance belong to a real search
    // service; trigram `ilike` is honest enough until then.
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurants')
        .select(restaurantColumns)
        .eq('service_area_id', areaId)
        .ilike('search_text', '%$q%')
        .order('rating', ascending: false);
    return rows.map(restaurantFromRow).toList(growable: false);
  }

}
