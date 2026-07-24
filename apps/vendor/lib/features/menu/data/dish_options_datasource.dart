import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/menu/domain/entities/dish_options.dart';

/// A dish's customisation — its variant and add-on groups (migration 0048).
///
/// Kept apart from [VendorMenuDataSource] deliberately: options attach to a dish
/// that already has an id, so this is a separate, on-demand read/write that the
/// main menu screen never needs, and the menu's tests never have to fake.
abstract interface class DishOptionsDataSource {
  /// The dish's groups (with their options), in the vendor's order. Reads the
  /// vendor's own dish through the `staff_restaurant_id()` policy, so a sold-out
  /// option is visible to be switched back on.
  Future<List<DishOptionGroup>> fetch(String dishId);

  /// Replace the dish's whole customisation in one call (`set_menu_item_options`).
  Future<void> save(String dishId, List<DishOptionGroup> groups);
}

class DishOptionsSupabaseDataSource implements DishOptionsDataSource {
  const DishOptionsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<DishOptionGroup>> fetch(String dishId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_option_groups')
        .select('name, min_select, max_select, rank, '
            'menu_options(name, price_delta, is_available, rank)')
        .eq('menu_item_id', dishId)
        // ascending is load-bearing: postgrest-dart's order() defaults to
        // descending. The embedded options are sorted in the entity.
        .order('rank', ascending: true);

    return rows.map(DishOptionGroup.fromJson).toList(growable: false);
  }

  @override
  Future<void> save(String dishId, List<DishOptionGroup> groups) async {
    await _db.rpc<void>(
      'set_menu_item_options',
      params: <String, dynamic>{
        'p_menu_item_id': dishId,
        'p_groups': <Map<String, dynamic>>[
          for (int i = 0; i < groups.length; i++) groups[i].toRpcJson(i),
        ],
      },
    );
  }
}
