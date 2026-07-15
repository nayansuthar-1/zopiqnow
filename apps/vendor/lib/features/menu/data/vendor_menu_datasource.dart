import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';

/// The vendor's side of `public.menu_items` — the rows a customer reads, plus
/// the sold-out ones they cannot, and the three verbs a customer never gets.
abstract interface class VendorMenuDataSource {
  /// The whole menu, grouped into sections in the vendor's order, *including*
  /// unavailable dishes — a kitchen that could not see a sold-out dish could
  /// never switch it back on.
  Future<List<VendorMenuSection>> fetchMenu(String restaurantId);

  /// Flip one dish on or off. The single most-used action on the screen, so it
  /// is its own call and not a round-trip through the whole editor.
  Future<void> setAvailability({
    required String dishId,
    required bool isAvailable,
  });

  /// Create ([VendorDish.isNew]) or update a dish. Returns it as the database
  /// stored it — for a new dish, that is the first time the id exists.
  Future<VendorDish> saveDish(VendorDish dish, {required String restaurantId});

  /// Remove a dish for good. Throws [MenuItemInUseFailure] when it appears on a
  /// past order and the database refuses to erase it.
  Future<void> deleteDish(String dishId);
}

/// A dish that cannot be deleted because an order still points at it. The FK
/// from `order_items` (migration 0003, no cascade) is doing its job — a receipt
/// must survive its dish — so the vendor is told to take it off the menu the
/// other way: mark it unavailable.
class MenuItemInUseFailure implements Exception {
  const MenuItemInUseFailure();
}

/// Any other write failure — an outage, a lost connection. The message is the
/// one the UI shows when it has nothing more specific to say.
class MenuWriteFailure implements Exception {
  const MenuWriteFailure([
    this.message = 'We couldn\'t save that change. Please try again.',
  ]);

  final String message;
}

class VendorMenuSupabaseDataSource implements VendorMenuDataSource {
  const VendorMenuSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Postgres raises this when a delete would orphan a row that references the
  /// one being removed — here, an `order_items` line pointing at the dish.
  static const String _foreignKeyViolation = '23503';

  static const String _columns =
      'id, name, description, price, is_veg, category, is_available';

  @override
  Future<List<VendorMenuSection>> fetchMenu(String restaurantId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select('$_columns, category_rank, item_rank')
        .eq('restaurant_id', restaurantId)
        // The vendor's merchandising order. `ascending: true` is load-bearing:
        // postgrest-dart's `order()` defaults to DESCENDING (the same trap the
        // customer datasource documents).
        .order('category_rank', ascending: true)
        .order('item_rank', ascending: true);

    // Insertion-ordered: a section appears in the position of its first dish,
    // which — rows already sorted by rank — is the vendor's category order.
    final Map<String, List<VendorDish>> sections =
        <String, List<VendorDish>>{};
    for (final Map<String, dynamic> row in rows) {
      sections
          .putIfAbsent(row['category'] as String, () => <VendorDish>[])
          .add(_toDish(row));
    }

    return sections.entries
        .map(
          (MapEntry<String, List<VendorDish>> e) =>
              VendorMenuSection(title: e.key, dishes: e.value),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setAvailability({
    required String dishId,
    required bool isAvailable,
  }) async {
    try {
      await _db
          .from('menu_items')
          .update(<String, dynamic>{'is_available': isAvailable})
          .eq('id', dishId);
    } on PostgrestException catch (e) {
      throw MenuWriteFailure(e.message);
    }
  }

  @override
  Future<VendorDish> saveDish(
    VendorDish dish, {
    required String restaurantId,
  }) async {
    // The dish's own fields. Its rank — where it sits in the menu — is not the
    // vendor's to type; it is computed so the dish lands at the end of its
    // section instead of jumping to the top of everyone's list.
    final Map<String, dynamic> fields = <String, dynamic>{
      'name': dish.name,
      'description': dish.description,
      'price': dish.price,
      'is_veg': dish.isVeg,
      'category': dish.category,
    };

    try {
      final _Placement place = await _placementFor(restaurantId, dish.category);

      if (dish.isNew) {
        final Map<String, dynamic> row = await _db
            .from('menu_items')
            .insert(<String, dynamic>{
              ...fields,
              'restaurant_id': restaurantId,
              'is_available': true,
              'category_rank': place.categoryRank,
              'item_rank': place.nextItemRank,
            })
            .select(_columns)
            .single();
        return _toDish(row);
      }

      // On edit, only `category_rank` is touched, and only so a dish moved to a
      // different section adopts that section's rank — otherwise it would keep
      // its old one and split the section in two on the customer's menu (which
      // groups by category but orders by rank). `item_rank` is left alone, so
      // editing a price does not send the dish to the bottom of its own list.
      final Map<String, dynamic> row = await _db
          .from('menu_items')
          .update(<String, dynamic>{
            ...fields,
            'category_rank': place.categoryRank,
          })
          .eq('id', dish.id)
          .select(_columns)
          .single();
      return _toDish(row);
    } on PostgrestException catch (e) {
      throw MenuWriteFailure(e.message);
    }
  }

  @override
  Future<void> deleteDish(String dishId) async {
    try {
      await _db.from('menu_items').delete().eq('id', dishId);
    } on PostgrestException catch (e) {
      if (e.code == _foreignKeyViolation) throw const MenuItemInUseFailure();
      throw MenuWriteFailure(e.message);
    }
  }

  /// Where a dish belongs in the menu ordering, for a given section. An existing
  /// section keeps its `category_rank` and the dish appends after its last item;
  /// a brand-new section is ranked after every existing one.
  Future<_Placement> _placementFor(String restaurantId, String category) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select('category, category_rank, item_rank')
        .eq('restaurant_id', restaurantId);

    int maxCategoryRank = -1;
    int? categoryRank;
    int maxItemRank = -1;
    for (final Map<String, dynamic> row in rows) {
      final int cRank = (row['category_rank'] as num).toInt();
      if (cRank > maxCategoryRank) maxCategoryRank = cRank;
      if (row['category'] == category) {
        categoryRank = cRank;
        final int iRank = (row['item_rank'] as num).toInt();
        if (iRank > maxItemRank) maxItemRank = iRank;
      }
    }

    return _Placement(
      categoryRank: categoryRank ?? maxCategoryRank + 1,
      nextItemRank: maxItemRank + 1,
    );
  }

  VendorDish _toDish(Map<String, dynamic> row) => VendorDish(
    id: row['id'] as String,
    name: row['name'] as String,
    description: row['description'] as String,
    price: (row['price'] as num).toInt(),
    isVeg: row['is_veg'] as bool,
    category: row['category'] as String,
    isAvailable: row['is_available'] as bool,
  );
}

class _Placement {
  const _Placement({required this.categoryRank, required this.nextItemRank});

  final int categoryRank;
  final int nextItemRank;
}
