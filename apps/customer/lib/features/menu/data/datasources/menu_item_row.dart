import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

/// The `menu_items` columns every dish query selects, and the one place a row of
/// them becomes a [MenuItem].
///
/// Shared because discovery reads dishes too. The menu screen asks for one
/// restaurant's dishes and the Recommended rail asks for the platform's, but a
/// dish is the same dish either way — and two copies of this mapping would be
/// two places to forget `gst_rate_bps` the day a slab moves.
///
/// `category` is deliberately not here: the menu screen groups by it and
/// discovery ranks by it, so each caller appends it (along with anything else it
/// needs) rather than every caller paying for both.
const String menuItemColumns =
    'id, name, description, price, is_veg, is_bestseller, rating, '
    'image_url, original_price, prep_minutes, gst_rate_bps, '
    // Variants & add-ons (0048). RLS returns only available options of a
    // visible dish, so nothing sold-out reaches the customer. Ordered in Dart.
    'menu_option_groups(id, name, min_select, max_select, rank, '
    'menu_options(id, name, price_delta, rank))';

/// Postgres row → domain entity. Numeric columns arrive as `num` (int or double
/// depending on the value), so every one is coerced explicitly.
MenuItem menuItemFromRow(Map<String, dynamic> row) => MenuItem(
  id: row['id'] as String,
  name: row['name'] as String,
  description: row['description'] as String,
  price: (row['price'] as num).toInt(),
  isVeg: row['is_veg'] as bool,
  isBestseller: row['is_bestseller'] as bool,
  // Null stays null: "unrated" is not "rated zero".
  rating: (row['rating'] as num?)?.toDouble(),
  imageUrl: row['image_url'] as String,
  originalPrice: (row['original_price'] as num?)?.toInt(),
  prepMinutes: (row['prep_minutes'] as num?)?.toInt(),
  gstRateBps: (row['gst_rate_bps'] as num?)?.toInt() ?? 500,
  optionGroups: menuOptionGroupsFrom(row['menu_option_groups']),
);

/// The dish's option groups, ranked, with any group left empty by RLS (all its
/// options sold out) dropped — a group with no answers is one the customer could
/// never satisfy.
List<MenuOptionGroup> menuOptionGroupsFrom(Object? raw) {
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
