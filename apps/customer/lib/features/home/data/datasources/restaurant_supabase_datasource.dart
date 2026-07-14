import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/home/data/datasources/restaurant_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_row.dart';
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

  @override
  Future<List<Restaurant>> fetchNearby() async {
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurants')
        .select(restaurantColumns)
        // `ascending: true` is not decoration: postgrest-dart's `order()`
        // defaults to DESCENDING, so the bare call put the farthest restaurants
        // at the top of the feed. Every `order` in this app states its direction.
        .order('distance_km', ascending: true);
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
  Future<List<Restaurant>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <Restaurant>[];

    // Matches the generated `search_text` column, so a query hits both the name
    // and the cuisine tags. Ranking and typo tolerance belong to a real search
    // service; trigram `ilike` is honest enough until then.
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurants')
        .select(restaurantColumns)
        .ilike('search_text', '%$q%')
        .order('rating', ascending: false);
    return rows.map(restaurantFromRow).toList(growable: false);
  }

}
