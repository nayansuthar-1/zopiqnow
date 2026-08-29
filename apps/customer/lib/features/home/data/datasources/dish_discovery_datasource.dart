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

  /// The id prefix migration 0140 mints every seeded bottled drink with, and the
  /// server-side half of `MenuItem.isBottledDrink`.
  ///
  /// Stated once here because two of the three queries below exclude it and one
  /// deliberately does not. It is filtered in SQL rather than in Dart because
  /// there are 192 of these rows against [fetchPool]'s ceiling of 600 — a third
  /// of the payload, fetched over mobile data to be dropped on arrival, which is
  /// the exact shape of the bug the `restaurantIds` scope already fixed once.
  static const String _bottledDrinkIdPrefix = 'bev-%';

  /// Candidate dishes for the Recommended rail, from the kitchens in
  /// [restaurantIds] and no others.
  ///
  /// **Scoped to the feed, and that is the fix rather than an optimisation.**
  /// This used to read the whole platform and let `joinDishes` throw away
  /// whatever came from another town — so a Sadri customer downloaded Hotel
  /// Wing Orbit's 228 Falna dishes, a third of the payload, to discard every one
  /// of them. Worse, they were discarded *after* the cap, so they were 228 of
  /// the 200 places two Sadri kitchens never got. Bharkadevi Ice Cream and
  /// Mamaji Snacks could not be recommended at all.
  ///
  /// The ordering is not what the customer sees — `rankDishes` re-sorts the
  /// whole pool against their search history before anything is shown. It
  /// decides which dishes make it into the pool at all if a town ever outgrows
  /// [limit], and each `order` earns its place there:
  ///
  ///  * bestsellers first, so the dishes a kitchen sells are never the ones cut;
  ///  * then rating, which does nothing today — no dish on the platform is rated
  ///    — but is what should decide once any of them is;
  ///  * then `id`, which is a uuid and therefore shuffles the kitchens together.
  ///    That is deliberate: a truncated pool samples the whole town instead of
  ///    filling up with whichever kitchen sorts first, which is the shape of bug
  ///    this method just had.
  ///
  /// [limit] sits above the largest town's whole menu (Sadri, 475 dishes), so
  /// nothing is dropped today. It is a ceiling against a runaway request, not a
  /// shortlist — a category page has its own query in [fetchCategory].
  ///
  /// Option groups ride along (see [menuItemColumns]) and are load-bearing here.
  /// The rail has its own ADD button, and a customisable dish added without its
  /// groups would go into the cart at its base price with no variant chosen —
  /// which `place_order` would then price differently from the card.
  Future<List<DishRow>> fetchPool({
    required List<String> restaurantIds,
    int limit = 600,
  }) async {
    // No town, no feed, no dishes — and no request. Home shows "set a location"
    // in this state, so a pool fetched here could only ever be discarded whole.
    if (restaurantIds.isEmpty) return const <DishRow>[];

    final List<Map<String, dynamic>> rows = await _db
        .from('menu_items')
        .select(_columns)
        .inFilter('restaurant_id', restaurantIds)
        // No bottled drinks in "Recommended for you". The menu feed stopped
        // drawing them and this rail did not, so the first two recommendations
        // on the home screen were a Limca and a Maaza — the platform
        // recommending its own seeded stock over the food a kitchen cooks.
        //
        // They are not ranked out, they are excluded: `rankDishes` re-sorts
        // against the phone's search history, and a customer with no history
        // gets the pool order, which these sort near the top of.
        .not('id', 'like', _bottledDrinkIdPrefix)
        // `ascending` is stated on every order in this app: postgrest-dart
        // defaults it to DESCENDING, which is what the first two want but is not
        // something a reader should have to know.
        .order('is_bestseller', ascending: false)
        // Nulls last, so unrated dishes fall to the back of the pool rather than
        // the front — "unrated" is not "rated zero", but it is not "best" either.
        .order('rating', ascending: false, nullsFirst: false)
        .order('id', ascending: true)
        .limit(limit);
    return rows.map(_toRow).toList(growable: false);
  }

  /// Every dish a category tile could contain, by dish name or menu section.
  ///
  /// A category page asks for its own category rather than filtering
  /// [fetchPool], and that is not an optimisation — it is the fix for "I tap
  /// Dosa and there is no dosa". The pool was capped at 200 of the 703 dishes on
  /// the platform and ordered by bestseller then rating; nothing is rated, so
  /// the ordering ran out after 42 rows and Postgres filled the rest in whatever
  /// order it liked. Whole kitchens never made the cut — the three dosas among
  /// them. [fetchPool] no longer truncates like that, but it is still the *feed's*
  /// dishes rather than a category's, and a category wants all of its own.
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
        // As in [fetchPool]. No tile means "cold drink" today — the drink-ish
        // ones are Shake, Lassi and Cold Coffee, all made to order — so this
        // empties nothing; it stops a seeded Limca turning up under Ice Cream
        // because both sit in a section somebody called "Beverages".
        .not('id', 'like', _bottledDrinkIdPrefix)
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
  ///
  /// **The bottled drinks are excluded here too**, like everywhere else.
  ///
  /// This one had an argument for the other side and lost it: somebody typing
  /// "coke" is asking by name, and answering with nothing is a dead end. But the
  /// instruction is that the seeded drinks are an add-on and not a product —
  /// they exist to be offered alongside food, not to be found, browsed or
  /// recommended — and a search result is a way of finding one.
  ///
  /// The consequence, stated rather than buried: **a drink cannot be ordered on
  /// its own.** The only routes to one are the strip after a dish goes in the
  /// cart and the rail on the cart page, and both require food in the basket
  /// first. Deleting this one filter is what reverses that.
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
        .not('id', 'like', _bottledDrinkIdPrefix)
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
