import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/menu/data/datasources/menu_item_row.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// A dish as it comes back from a cross-restaurant query: the dish itself, plus
/// the two columns needed to place it — which kitchen it belongs to and which
/// section of that kitchen's menu it sits in.
///
/// A record and not a class because it exists for the length of one join. The
/// providers turn it into a `DishSuggestion`, which is the thing the UI holds.
typedef DishRow = ({MenuItem item, String restaurantId, String category});

/// Dishes across every restaurant, rather than within one.
///
/// The menu screen's data source (`MenuSupabaseDataSource`) answers "what does
/// this restaurant serve?". This one answers the two questions discovery asks:
/// "what is worth recommending?" and "who serves something called this?".
///
/// Both read `menu_items`, whose public policy (0032) already limits the answer
/// to available dishes of active restaurants — so neither query carries an
/// `is_available` filter it could not be trusted to apply anyway.
class DishDiscoveryDataSource {
  const DishDiscoveryDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// `restaurant_id` to join on, `category` to rank by.
  static const String _columns = '$menuItemColumns, restaurant_id, category';

  /// Candidate dishes for the Recommended rail.
  ///
  /// The ordering is not what the customer sees — `rankDishes` re-sorts the
  /// whole pool against their search history before anything is shown. It is
  /// what decides which dishes make it into the pool at all when a platform
  /// outgrows [limit], and "the bestsellers, then the best-rated" is the right
  /// answer to that: a dish nobody ordered and nobody rated is the one to drop.
  ///
  /// [limit] is well below the visible menu — 200 of 703 dishes — so this *is*
  /// a shortlist, and a thin one: nothing on the platform is rated and only 42
  /// dishes are bestsellers, so the ordering runs out and the tiebreak decides
  /// most of the pool. Category pages no longer read it for that reason; they
  /// ask `fetchCategory` for their own category instead.
  ///
  /// Option groups ride along (see [menuItemColumns]) and are load-bearing here.
  /// The rail has its own ADD button, and a customisable dish added without its
  /// groups would go into the cart at its base price with no variant chosen —
  /// which `place_order` would then price differently from the card.
  Future<List<DishRow>> fetchPool({int limit = 200}) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select(_columns)
        // `ascending` is stated on every order in this app: postgrest-dart
        // defaults it to DESCENDING, which is what these two want but is not
        // something a reader should have to know.
        .order('is_bestseller', ascending: false)
        // Nulls last, so unrated dishes fall to the back of the pool rather than
        // the front — "unrated" is not "rated zero", but it is not "best" either.
        .order('rating', ascending: false, nullsFirst: false)
        // The tiebreak, and it is not decoration: with nothing on the platform
        // rated, it is what picks 158 of the 200 rows. Stated so the pool is the
        // same pool on every launch rather than whatever order Postgres returns.
        .order('id', ascending: true)
        .limit(limit);
    return rows.map(_toRow).toList(growable: false);
  }

  /// Every dish a category tile could contain, by dish name or menu section.
  ///
  /// A category page asks for its own category rather than filtering the
  /// [fetchPool] shortlist, and that is not an optimisation — it is the fix for
  /// "I tap Dosa and there is no dosa". The pool is capped at 200 of the 703
  /// dishes on the platform and ordered by bestseller then rating; nothing is
  /// rated, so the ordering ran out after 42 rows and Postgres filled the rest
  /// in whatever order it liked. Whole kitchens never made the cut — the three
  /// dosas among them.
  ///
  /// [needles] come from `categoryNeedle`, so each is a prefix of every spelling
  /// the client rule accepts: `ilike` returns a superset here and `hasTerm`
  /// narrows it, which is what stops "Classic Cakes" reaching the Lassi tile
  /// while "Milkshakes" still reaches Shake.
  ///
  /// [limit] is a stable ceiling rather than a shortlist — the widest tile today
  /// is Cake at 84 dishes. Bestsellers first so a truncation that does one day
  /// happen drops the least interesting rows, then `id` so the same request
  /// twice returns the same dishes.
  Future<List<DishRow>> fetchCategory(
    List<String> needles, {
    int limit = 300,
  }) async {
    final List<String> clean = needles
        .map(_sanitize)
        .where((String n) => n.isNotEmpty)
        .toList(growable: false);
    if (clean.isEmpty) return const <DishRow>[];

    final String filter = clean
        .map((String n) => 'name.ilike.%$n%,category.ilike.%$n%')
        .join(',');

    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select(_columns)
        .or(filter)
        .order('is_bestseller', ascending: false)
        .order('id', ascending: true)
        .limit(limit);
    return rows.map(_toRow).toList(growable: false);
  }

  /// Dishes matching a typed query, by dish name, menu section, or description.
  ///
  /// Three fields and not one: "biryani" should find the Biryani section of a
  /// menu whose dishes are all called "Paradise Special", and "paneer" should
  /// find a dish whose description is the only place the word appears. Ranking
  /// among the hits is the client's job — this returns candidates, and
  /// `rankDishes` decides which of them the customer reads first.
  Future<List<DishRow>> search(String query, {int limit = 40}) async {
    final String needle = _sanitize(query);
    if (needle.isEmpty) return const <DishRow>[];

    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select(_columns)
        .or(
          'name.ilike.%$needle%,'
          'category.ilike.%$needle%,'
          'description.ilike.%$needle%',
        )
        .order('is_bestseller', ascending: false)
        .order('rating', ascending: false, nullsFirst: false)
        .limit(limit);
    return rows.map(_toRow).toList(growable: false);
  }

  /// PostgREST's `or=` is a comma-separated list of dotted triples, so a comma,
  /// a bracket or a quote in the query is not a character to match — it is
  /// syntax, and it would either error or change which filters run. Dropping
  /// those four is enough; `%` and `_` stay, matching what a query does on the
  /// restaurant search's `ilike`, where they are wildcards rather than a way in.
  static String _sanitize(String query) =>
      query.trim().replaceAll(RegExp(r'[,()"]'), '').trim();

  static DishRow _toRow(Map<String, dynamic> row) => (
    item: menuItemFromRow(row),
    restaurantId: row['restaurant_id'] as String,
    category: row['category'] as String,
  );
}
