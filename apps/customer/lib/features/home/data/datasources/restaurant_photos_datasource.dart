import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/core/storage/json_disk_cache.dart';

/// A few dish photographs per restaurant, for the Home card's photo strip.
///
/// One request for the whole feed rather than one per card. The shape — "the
/// first N rows of each group" — is not something PostgREST can ask for, so this
/// goes through `restaurant_card_photos` (0119); see that migration for why the
/// function is `security invoker` and what bounds its size.
class RestaurantPhotosDataSource {
  const RestaurantPhotosDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Dish photo URLs keyed by restaurant id, in the order the card shows them.
  ///
  /// Cached to disk beside the feed itself and for the same reason: this is the
  /// first screen, and on a dead connection the difference is a catalogue that
  /// opens with pictures rather than one that opens with gradients. Stale is
  /// fine — a dish photo changing is not news, and the card falls back to the
  /// restaurant's own cover for anything that has gone.
  ///
  /// **Failure here is not failure of the feed.** A restaurant card is complete
  /// without a photo strip, so a caller that cannot get these should show the
  /// cards anyway; the provider above this turns an error into an empty map
  /// rather than an error state.
  Future<Map<String, List<String>>> fetch() async {
    final List<Map<String, dynamic>> rows = await JsonDiskCache.rows(
      key: 'restaurant_card_photos',
      // The default is the function's own — five, which with the restaurant's
      // cover in front of it makes the six pages the card is willing to draw.
      fetch: () async => List<Map<String, dynamic>>.from(
        await _db.rpc<dynamic>('restaurant_card_photos') as List<dynamic>,
      ),
    );

    final Map<String, List<String>> byRestaurant = <String, List<String>>{};
    for (final Map<String, dynamic> row in rows) {
      final String id = row['restaurant_id'] as String;
      final String url = row['image_url'] as String;
      if (url.isEmpty) continue;
      byRestaurant.putIfAbsent(id, () => <String>[]).add(url);
    }
    return byRestaurant;
  }
}
