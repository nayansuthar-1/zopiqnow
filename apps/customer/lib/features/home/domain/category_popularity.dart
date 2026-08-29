/// Ordering the home screen's food tiles by what the town actually buys.
///
/// The tiles shipped in a hand-written order — Sandwich, Pizza, Burger, Momos,
/// Pav Bhaji, Dosa — which was somebody's guess from before the platform had a
/// single customer. `dish_order_counts` (migration 0145) answers what has been
/// sold; this turns that into a tile order.
///
/// Pure: no Riverpod, no Supabase, no clock. The counts and the vocabulary are
/// arguments, so the same inputs always give the same order — which matters more
/// here than usual, because a rail that reorders itself between two rebuilds
/// looks broken rather than personalised.
library;

import 'package:zopiqnow/features/home/domain/category_matching.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// One line of "this has been sold, this much" — a frozen dish name, the menu
/// section it was sold from, and the units.
typedef DishOrderCount = ({String dishName, String section, int units});

/// [categories] reordered so the most-ordered food leads, keeping every tile.
///
/// **Nothing is dropped and nothing is invented.** This is a sort, so a tile
/// nobody has ever ordered still appears; it simply sits where it always did,
/// relative to the other tiles nobody has ordered.
///
/// Three rules, in this order, and each is load-bearing:
///
/// 1. **"View More" is always last.** It is a door, not a food. Sorting it by
///    popularity would be sorting a control by how much of it people eat, and
///    it would land in the middle of the rail the moment anything scored zero.
///
/// 2. **Meat and egg stay after every vegetarian tile.** That was an explicit
///    call, not an accident of the old order: the four of them match zero dishes
///    in the whole catalogue today, so each opens an empty page, and a Mutton
///    tile four rows into a veg-majority town's home screen is not what popularity
///    is being asked to decide. Popularity orders them *among themselves*.
///
/// 3. **Then units sold, descending; ties keep the order they came in.** The
///    tie-break is the whole reason this is safe to ship on thin data. With
///    fifteen units sold across five dishes on the entire platform, almost every
///    tile ties on zero and therefore does not move at all — the hand-written
///    order survives exactly where there is nothing to say, and asserts itself
///    only where something has actually been sold. It improves on its own as
///    orders accumulate, with no further change here.
///
/// [vocabulary] is every tile the app ships, unfiltered — `namedDishMatchesCategory`
/// reads it to decide whether a dish's own name already names some *other* tile,
/// which is what stops "Shiv Special Lassi" in a *Shakes & Beverages* section
/// counting towards Shake.
List<FoodCategory> orderByPopularity({
  required List<FoodCategory> categories,
  required List<DishOrderCount> counts,
  required List<FoodCategory> vocabulary,
}) {
  if (counts.isEmpty) return categories;

  final Map<String, int> units = <String, int>{
    for (final FoodCategory c in categories)
      c.id: _unitsFor(c, counts, vocabulary),
  };

  // The incoming position, so ties are broken by the order the caller shipped
  // rather than by whatever `sort` does with equal elements.
  final Map<String, int> position = <String, int>{
    for (int i = 0; i < categories.length; i++) categories[i].id: i,
  };

  int rank(FoodCategory c) {
    if (c.id == _viewMoreId) return 2;
    return c.isVeg ? 0 : 1;
  }

  return List<FoodCategory>.of(categories)..sort((FoodCategory a, FoodCategory b) {
    final int byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;

    final int byUnits = units[b.id]!.compareTo(units[a.id]!);
    if (byUnits != 0) return byUnits;

    return position[a.id]!.compareTo(position[b.id]!);
  });
}

/// Units sold that belong to [category], by the app's one matching rule.
///
/// A line can count towards more than one tile — "Paneer Tikka Pizza" is both
/// Pizza and Paneer Tikka — and that is right: both tiles genuinely lead to it,
/// so both have earned the position. This is a popularity sort, not a partition.
int _unitsFor(
  FoodCategory category,
  List<DishOrderCount> counts,
  List<FoodCategory> vocabulary,
) {
  int total = 0;
  for (final DishOrderCount c in counts) {
    if (namedDishMatchesCategory(
      name: c.dishName,
      section: c.section,
      category: category,
      vocabulary: vocabulary,
    )) {
      total += c.units;
    }
  }
  return total;
}

const String _viewMoreId = 'view_more';
