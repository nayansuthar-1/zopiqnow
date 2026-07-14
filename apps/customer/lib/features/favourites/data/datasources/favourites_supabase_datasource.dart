import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/favourites/data/datasources/favourites_datasource.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_row.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Favourites, on Postgres.
class FavouritesSupabaseDataSource implements FavouritesDataSource {
  const FavouritesSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<Restaurant>> fetchFavourites() async {
    // Signed out, RLS returns nothing anyway — but browsing needs no account, so
    // most callers *are* signed out, and saying so here saves them a round trip.
    if (_db.auth.currentUser == null) return const <Restaurant>[];

    final List<Map<String, dynamic>> rows = await _db
        .from('favourites')
        // The restaurant, embedded through the foreign key. One round trip, and
        // the same columns and the same mapper the catalog uses — a favourite
        // renders as a restaurant card because it *is* a restaurant.
        .select('restaurants($restaurantColumns)')
        .order('created_at', ascending: false);

    return rows
        // A favourited restaurant that has since been delisted embeds as null:
        // the catalog policy is `using (is_active)`. It is not an error and it
        // is not a card — it is a restaurant that is no longer there, so it
        // simply stops being listed.
        .map((Map<String, dynamic> r) => r['restaurants'])
        .whereType<Map<String, dynamic>>()
        .map(restaurantFromRow)
        .toList(growable: false);
  }

  @override
  Future<void> addFavourite(String restaurantId) => _db
      .from('favourites')
      .upsert(<String, dynamic>{
        // Refused by the insert policy's `with check` if it is not the caller's
        // own id, so a bug here is a failed write rather than a favourite filed
        // under someone else's account.
        'user_id': _db.auth.currentUser!.id,
        'restaurant_id': restaurantId,
      }, ignoreDuplicates: true);

  @override
  Future<void> removeFavourite(String restaurantId) => _db
      .from('favourites')
      .delete()
      // No `.eq('user_id', …)`: the delete policy already restricts this to the
      // caller's rows, and a second copy of that rule could only drift from it.
      .eq('restaurant_id', restaurantId);
}
