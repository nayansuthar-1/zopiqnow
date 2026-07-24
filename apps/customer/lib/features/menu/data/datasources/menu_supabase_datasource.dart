import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/menu/data/datasources/menu_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

/// The real menu: `public.menu_items` over PostgREST.
///
/// Postgres returns rows, but the screen renders sections. The grouping happens
/// here — in the data layer, where shape-mapping belongs — rather than making
/// every widget above understand a flat list.
class MenuSupabaseDataSource implements MenuDataSource {
  const MenuSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<MenuCategory>> fetchMenu(String restaurantId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select(
          'id, name, description, price, is_veg, is_bestseller, rating, '
          'image_url, category, '
          // Variants & add-ons (0048). RLS returns only available options of a
          // visible dish, so nothing sold-out reaches the menu. Ordered in Dart.
          'menu_option_groups(id, name, min_select, max_select, rank, '
          'menu_options(id, name, price_delta, rank))',
        )
        .eq('restaurant_id', restaurantId)
        // The vendor's merchandising order, not ours: "Recommended" leads
        // because they ranked it first, and sorting by price would overrule them.
        //
        // `ascending: true` is load-bearing — postgrest-dart's `order()` defaults
        // to DESCENDING, and the bare version shipped Desserts above Recommended
        // to the device.
        .order('category_rank', ascending: true)
        .order('item_rank', ascending: true);

    // Insertion-ordered: sections come out in the order their first dish
    // appeared, which is the vendor's category order.
    final Map<String, List<MenuItem>> sections = <String, List<MenuItem>>{};
    for (final Map<String, dynamic> row in rows) {
      sections
          .putIfAbsent(row['category'] as String, () => <MenuItem>[])
          .add(_toMenuItem(row));
    }

    return sections.entries
        .map(
          (MapEntry<String, List<MenuItem>> e) =>
              MenuCategory(title: e.key, items: e.value),
        )
        .toList(growable: false);
  }

  MenuItem _toMenuItem(Map<String, dynamic> row) => MenuItem(
    id: row['id'] as String,
    name: row['name'] as String,
    description: row['description'] as String,
    price: (row['price'] as num).toInt(),
    isVeg: row['is_veg'] as bool,
    isBestseller: row['is_bestseller'] as bool,
    // Null stays null: "unrated" is not "rated zero".
    rating: (row['rating'] as num?)?.toDouble(),
    imageUrl: row['image_url'] as String,
    optionGroups: _toGroups(row['menu_option_groups']),
  );

  /// The dish's option groups, ranked, with any group left empty by RLS (all its
  /// options sold out) dropped — a group with no answers is one the customer
  /// could never satisfy.
  static List<MenuOptionGroup> _toGroups(Object? raw) {
    final List<Map<String, dynamic>> rows =
        (raw as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (Map<String, dynamic> a, Map<String, dynamic> b) =>
                ((a['rank'] as num?)?.toInt() ?? 0)
                    .compareTo((b['rank'] as num?)?.toInt() ?? 0),
          );
    return rows
        .map(MenuOptionGroup.fromJson)
        .where((MenuOptionGroup g) => g.options.isNotEmpty)
        .toList(growable: false);
  }
}
