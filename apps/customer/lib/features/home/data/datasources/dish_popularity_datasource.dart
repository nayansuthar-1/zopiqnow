import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/home/domain/category_popularity.dart';

/// What the town has actually been ordering, for the home tiles to sort by.
///
/// Reads `dish_order_counts` (migration 0145), which returns aggregate units per
/// sold dish name and menu section — no user, no order, no restaurant. The
/// bucketing into tiles is `orderByPopularity`'s job, using the same matching
/// rule the rest of the app uses; this only fetches.
class DishPopularityDataSource {
  const DishPopularityDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Units sold per dish over the last [days].
  ///
  /// Ninety days by default: long enough that a quiet week does not reshuffle
  /// the home screen, short enough that last winter's favourite is not still
  /// leading in summer.
  ///
  /// **Empty on failure, deliberately.** The only thing this decides is the
  /// order of tiles that are all present either way, and `orderByPopularity`
  /// answers an empty list by returning the hand-written order untouched. A home
  /// screen that will not load because a sort hint timed out would be a far
  /// worse trade than a home screen in its default order.
  Future<List<DishOrderCount>> fetchCounts({int days = 90}) async {
    try {
      final List<dynamic> rows = await _db.rpc<List<dynamic>>(
        'dish_order_counts',
        params: <String, dynamic>{'p_days': days},
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> r) => (
              dishName: r['dish_name'] as String? ?? '',
              section: r['section'] as String? ?? '',
              units: (r['units'] as num?)?.toInt() ?? 0,
            ),
          )
          .where((DishOrderCount c) => c.dishName.isNotEmpty && c.units > 0)
          .toList(growable: false);
    } on Object {
      return const <DishOrderCount>[];
    }
  }
}
