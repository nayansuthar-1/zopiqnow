import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/core/storage/json_disk_cache.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_item_row.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';

/// The real menu: `public.menu_items` over PostgREST.
///
/// Postgres returns rows, but the screen renders sections. The grouping happens
/// here — in the data layer, where shape-mapping belongs — rather than making
/// every widget above understand a flat list.
class MenuSupabaseDataSource implements MenuDataSource {
  const MenuSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Cached per restaurant. A menu is the heaviest read in the app and the one
  /// a customer returns to most — reopening the kitchen they ordered from last
  /// week should not wait on the network.
  ///
  /// Two minutes rather than the catalogue's five: a dish going out of stock is
  /// the change a customer notices, and they notice it by adding it to a cart
  /// that then refuses at checkout. `place_order` reprices and revalidates every
  /// line server-side (S4), so a stale menu can never sell anything at the wrong
  /// price — but it can waste somebody's time, and two minutes bounds that.
  @override
  Future<List<MenuCategory>> fetchMenu(String restaurantId) async {
    final List<Map<String, dynamic>> rows = await JsonDiskCache.rows(
      key: 'menu_$restaurantId',
      freshFor: const Duration(minutes: 2),
      fetch: () async => _db
          .from('menu_items')
          .select('$menuItemColumns, category')
          .eq('restaurant_id', restaurantId)
          // The vendor's merchandising order, not ours: "Recommended" leads
          // because they ranked it first, and sorting by price would overrule
          // them.
          //
          // `ascending: true` is load-bearing — postgrest-dart's `order()`
          // defaults to DESCENDING, and the bare version shipped Desserts above
          // Recommended to the device.
          .order('category_rank', ascending: true)
          .order('item_rank', ascending: true),
    );

    // Insertion-ordered: sections come out in the order their first dish
    // appeared, which is the vendor's category order.
    final Map<String, List<MenuItem>> sections = <String, List<MenuItem>>{};
    for (final Map<String, dynamic> row in rows) {
      sections
          .putIfAbsent(row['category'] as String, () => <MenuItem>[])
          .add(menuItemFromRow(row));
    }

    return sections.entries
        .map(
          (MapEntry<String, List<MenuItem>> e) =>
              MenuCategory(title: e.key, items: e.value),
        )
        .toList(growable: false);
  }

  /// An RPC and not a select: `reviews` has RLS on with no select policy at all
  /// (0062), so there is nothing to read from. `restaurant_reviews` returns four
  /// columns and a first name, and cannot leak a fifth.
  @override
  Future<List<RestaurantReview>> fetchReviews(String restaurantId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'restaurant_reviews',
      params: <String, dynamic>{'p_restaurant_id': restaurantId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(RestaurantReview.fromJson)
        .toList(growable: false);
  }
}
