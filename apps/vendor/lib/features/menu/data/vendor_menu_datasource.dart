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
  ///
  /// [reason] is the kitchen's note on *why* it went off, written only when the
  /// dish is going off — switching a dish back on clears it, because a stale
  /// "paneer is over" on a dish that is selling again is worse than no note.
  Future<void> setAvailability({
    required String dishId,
    required bool isAvailable,
    String reason = '',
  });

  /// Create ([VendorDish.isNew]) or update a dish. Returns it as the database
  /// stored it — for a new dish, that is the first time the id exists.
  Future<VendorDish> saveDish(VendorDish dish, {required String restaurantId});

  /// Remove a dish for good. Throws [MenuItemInUseFailure] when it appears on a
  /// past order and the database refuses to erase it.
  Future<void> deleteDish(String dishId);

  /// Set the menu's section order. Every dish in `orderedTitles[i]` takes rank
  /// `i`, so the whole menu re-sorts to the order the vendor dragged the sections
  /// into. `orderedTitles` is every section, in the new order.
  Future<void> reorderCategories({
    required String restaurantId,
    required List<String> orderedTitles,
  });

  /// Rename a section — change the `category` text across every dish in it. The
  /// caller guarantees `to` is non-empty and not already another section's name;
  /// renaming onto an existing section would silently merge two sections whose
  /// ranks differ, and the screen prevents that before it gets here.
  Future<void> renameCategory({
    required String restaurantId,
    required String from,
    required String to,
  });

  /// Turn a whole section on or off — the `category_available` switch, written
  /// across every dish in the section at once (migration 0016).
  Future<void> setCategoryAvailability({
    required String restaurantId,
    required String category,
    required bool isAvailable,
  });
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
      'id, name, description, price, is_veg, is_bestseller, category, '
      'is_available, image_url, original_price, unavailable_reason, '
      'prep_minutes, serve_from, serve_to';

  @override
  Future<List<VendorMenuSection>> fetchMenu(String restaurantId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select('$_columns, category_available, category_rank, item_rank')
        .eq('restaurant_id', restaurantId)
        // The vendor's merchandising order. `ascending: true` is load-bearing:
        // postgrest-dart's `order()` defaults to DESCENDING (the same trap the
        // customer datasource documents).
        .order('category_rank', ascending: true)
        .order('item_rank', ascending: true);

    // Insertion-ordered: a section appears in the position of its first dish,
    // which — rows already sorted by rank — is the vendor's category order. Its
    // on/off state is shared by every row, so the first one to arrive settles it.
    final Map<String, List<VendorDish>> sections =
        <String, List<VendorDish>>{};
    final Map<String, bool> available = <String, bool>{};
    for (final Map<String, dynamic> row in rows) {
      final String category = row['category'] as String;
      sections.putIfAbsent(category, () => <VendorDish>[]).add(_toDish(row));
      available.putIfAbsent(
        category,
        () => row['category_available'] as bool,
      );
    }

    return sections.entries
        .map(
          (MapEntry<String, List<VendorDish>> e) => VendorMenuSection(
            title: e.key,
            dishes: e.value,
            isAvailable: available[e.key] ?? true,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setAvailability({
    required String dishId,
    required bool isAvailable,
    String reason = '',
  }) async {
    try {
      await _db
          .from('menu_items')
          .update(<String, dynamic>{
            'is_available': isAvailable,
            // Coming back on always clears the note; going off writes whatever
            // the caller has (often '' — the switch is one tap and does not stop
            // to ask, so the reason arrives later or not at all).
            'unavailable_reason': isAvailable ? '' : reason,
          })
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
      'is_bestseller': dish.isBestseller,
      'category': dish.category,
      'image_url': dish.imageUrl,
      // Nulls are sent, not omitted: clearing a struck-through price or a
      // serving window has to reach the row, and a key left out of a PostgREST
      // patch leaves the old value sitting there.
      'original_price': dish.originalPrice,
      'prep_minutes': dish.prepMinutes,
      'serve_from': _toPgTime(dish.serveFromMinutes),
      'serve_to': _toPgTime(dish.serveToMinutes),
      'unavailable_reason': dish.unavailableReason,
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
              // A dish added to a section that is currently switched off stays
              // off with it — otherwise it would be the one item showing under a
              // heading the vendor took down.
              'category_available': place.categoryAvailable,
              'category_rank': place.categoryRank,
              'item_rank': place.nextItemRank,
            })
            .select(_columns)
            .single();
        return _toDish(row);
      }

      // On edit, `category_rank` and `category_available` follow the section, and
      // only so a dish *moved* to a different section adopts that section's rank
      // and on/off state — otherwise it would keep its old ones and split the
      // section in two on the customer's menu (which groups by category but
      // orders by rank). `item_rank` is left alone, so editing a price does not
      // send the dish to the bottom of its own list.
      final Map<String, dynamic> row = await _db
          .from('menu_items')
          .update(<String, dynamic>{
            ...fields,
            'category_available': place.categoryAvailable,
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

  @override
  Future<void> reorderCategories({
    required String restaurantId,
    required List<String> orderedTitles,
  }) async {
    try {
      // One statement per section — a handful, not a table scan. Each stamps the
      // section's new position onto every dish in it, which is how the flat list
      // re-sorts to the order the vendor dragged the sections into.
      for (int rank = 0; rank < orderedTitles.length; rank++) {
        await _db
            .from('menu_items')
            .update(<String, dynamic>{'category_rank': rank})
            .eq('restaurant_id', restaurantId)
            .eq('category', orderedTitles[rank]);
      }
    } on PostgrestException catch (e) {
      throw MenuWriteFailure(e.message);
    }
  }

  @override
  Future<void> renameCategory({
    required String restaurantId,
    required String from,
    required String to,
  }) async {
    try {
      await _db
          .from('menu_items')
          .update(<String, dynamic>{'category': to})
          .eq('restaurant_id', restaurantId)
          .eq('category', from);
    } on PostgrestException catch (e) {
      throw MenuWriteFailure(e.message);
    }
  }

  @override
  Future<void> setCategoryAvailability({
    required String restaurantId,
    required String category,
    required bool isAvailable,
  }) async {
    try {
      await _db
          .from('menu_items')
          .update(<String, dynamic>{'category_available': isAvailable})
          .eq('restaurant_id', restaurantId)
          .eq('category', category);
    } on PostgrestException catch (e) {
      throw MenuWriteFailure(e.message);
    }
  }

  /// Where a dish belongs in the menu ordering, for a given section. An existing
  /// section keeps its `category_rank` and its on/off state, and the dish appends
  /// after its last item; a brand-new section is ranked after every existing one
  /// and starts on.
  Future<_Placement> _placementFor(String restaurantId, String category) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select('category, category_available, category_rank, item_rank')
        .eq('restaurant_id', restaurantId);

    int maxCategoryRank = -1;
    int? categoryRank;
    bool categoryAvailable = true;
    int maxItemRank = -1;
    for (final Map<String, dynamic> row in rows) {
      final int cRank = (row['category_rank'] as num).toInt();
      if (cRank > maxCategoryRank) maxCategoryRank = cRank;
      if (row['category'] == category) {
        categoryRank = cRank;
        categoryAvailable = row['category_available'] as bool;
        final int iRank = (row['item_rank'] as num).toInt();
        if (iRank > maxItemRank) maxItemRank = iRank;
      }
    }

    return _Placement(
      categoryRank: categoryRank ?? maxCategoryRank + 1,
      categoryAvailable: categoryAvailable,
      nextItemRank: maxItemRank + 1,
    );
  }

  VendorDish _toDish(Map<String, dynamic> row) => VendorDish(
    id: row['id'] as String,
    name: row['name'] as String,
    description: row['description'] as String,
    price: (row['price'] as num).toInt(),
    isVeg: row['is_veg'] as bool,
    isBestseller: row['is_bestseller'] as bool? ?? false,
    category: row['category'] as String,
    isAvailable: row['is_available'] as bool,
    imageUrl: row['image_url'] as String? ?? '',
    originalPrice: (row['original_price'] as num?)?.toInt(),
    unavailableReason: row['unavailable_reason'] as String? ?? '',
    prepMinutes: (row['prep_minutes'] as num?)?.toInt(),
    serveFromMinutes: _fromPgTime(row['serve_from']),
    serveToMinutes: _fromPgTime(row['serve_to']),
  );

  /// Minutes since midnight → the `HH:MM:SS` a Postgres `time` column takes.
  /// Null passes straight through: no window is the common case and the column
  /// is nullable for exactly that reason.
  static String? _toPgTime(int? minutes) {
    if (minutes == null) return null;
    final String h = '${minutes ~/ 60}'.padLeft(2, '0');
    final String m = '${minutes % 60}'.padLeft(2, '0');
    return '$h:$m:00';
  }

  /// The other direction. PostgREST hands a `time` back as `HH:MM:SS`, and
  /// anything it cannot parse is treated as no window rather than a crash — a
  /// malformed time should cost the vendor a chip on a row, not the screen.
  static int? _fromPgTime(Object? raw) {
    if (raw is! String) return null;
    final List<String> parts = raw.split(':');
    if (parts.length < 2) return null;
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

class _Placement {
  const _Placement({
    required this.categoryRank,
    required this.categoryAvailable,
    required this.nextItemRank,
  });

  final int categoryRank;
  final bool categoryAvailable;
  final int nextItemRank;
}
