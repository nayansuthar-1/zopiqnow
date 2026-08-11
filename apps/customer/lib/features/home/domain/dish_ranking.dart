/// How "Recommended for you" and dish search decide what to put first.
///
/// Two callers, one function, because they are the same question asked about
/// different interests: the rail scores dishes against what this phone has been
/// searching for lately, and the search screen scores them against the words
/// being typed right now. Splitting them would have meant two definitions of
/// "this dish is about biryani" that could drift apart.
///
/// Pure — no Riverpod, no Supabase, no clock. Everything that varies (the
/// interests, the rotation) is an argument, so the same inputs always produce
/// the same order.
library;

import 'dart:math' as math;

import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';

/// Scores [pool] against [interests] and returns it sorted, best first.
///
/// [interests] is most-important-first: the rail passes recent searches newest
/// first, and search passes the single live query. An empty list is fine and
/// common — a customer who has never searched still gets a rail, ordered by
/// quality and [rotation] alone.
///
/// [rotation] is what keeps a fresh rail from being the same rail forever. It
/// seeds a small per-dish jitter, so changing it reshuffles the dishes that
/// scored close together without ever letting a bad dish outrank a good one.
/// Pass the day number to rotate daily; pass 0 — the default — to disable the
/// jitter entirely, which is what search wants, since a result order that
/// changes for reasons the customer cannot see is a bug on a search screen.
List<DishSuggestion> rankDishes({
  required List<DishSuggestion> pool,
  required List<String> interests,
  int rotation = 0,
}) {
  final List<String> terms = interests
      .map(_normalize)
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);

  final List<DishSuggestion> ranked = List<DishSuggestion>.of(pool);
  final Map<String, double> scores = <String, double>{
    for (final DishSuggestion d in ranked)
      d.item.id:
          _affinity(d, terms) * _affinityWeight +
          _quality(d) +
          _jitter(d.item.id, rotation),
  };

  ranked.sort((DishSuggestion a, DishSuggestion b) {
    final int byScore = scores[b.item.id]!.compareTo(scores[a.item.id]!);
    // Ties broken by id, not left to the sort: a stable order is what stops the
    // rail from shuffling between two rebuilds that scored everything the same.
    return byScore != 0 ? byScore : a.item.id.compareTo(b.item.id);
  });
  return ranked;
}

/// Takes the first [limit] of an already-ranked list, letting no single kitchen
/// contribute more than [perRestaurant] dishes.
///
/// Without the cap the rail is whichever restaurant happens to have the most
/// well-rated dishes, ten times over — which reads as a paid placement rather
/// than a recommendation, and buries every other kitchen on the platform.
///
/// The cap is a preference and not a rule: if honouring it would leave the rail
/// short, the dishes it held back come off the bench in rank order. A platform
/// with three restaurants should still fill a row.
List<DishSuggestion> diversify(
  List<DishSuggestion> ranked, {
  int perRestaurant = 2,
  int limit = 12,
}) {
  final List<DishSuggestion> picked = <DishSuggestion>[];
  final List<DishSuggestion> benched = <DishSuggestion>[];
  final Map<String, int> perKitchen = <String, int>{};

  for (final DishSuggestion d in ranked) {
    if (picked.length == limit) break;
    final int used = perKitchen[d.restaurant.id] ?? 0;
    if (used >= perRestaurant) {
      benched.add(d);
      continue;
    }
    perKitchen[d.restaurant.id] = used + 1;
    picked.add(d);
  }

  for (final DishSuggestion d in benched) {
    if (picked.length == limit) break;
    picked.add(d);
  }
  return List<DishSuggestion>.unmodifiable(picked);
}

/// How much a search match outweighs a good rating.
///
/// Deliberately lopsided. [_quality] tops out near 1.35 and one solid name match
/// on the newest search is worth 3.0, so a well-matched dish from an average
/// kitchen beats the platform's best-rated dish that has nothing to do with what
/// the customer was looking for. That is the whole point of the section: if the
/// last thing you searched was "biryani", biryani goes first.
const double _affinityWeight = 3.0;

/// How much a dish looks like the things the customer has been searching for.
///
/// Each interest contributes its best field match, discounted by how old it is,
/// and the total is capped — so five searches for five different things cannot
/// add up to a score no single strong match could reach.
double _affinity(DishSuggestion dish, List<String> terms) {
  if (terms.isEmpty) return 0;

  final String name = dish.item.name.toLowerCase();
  final String category = dish.category.toLowerCase();
  final String description = dish.item.description.toLowerCase();
  final String restaurantName = dish.restaurant.name.toLowerCase();
  final String cuisines = dish.restaurant.cuisines
      .join(' ')
      .toLowerCase();

  double total = 0;
  for (int i = 0; i < terms.length; i++) {
    // Newest first, and the fall-off is gentle: the fifth-most-recent search is
    // still worth 40% of the newest, because a taste is not a single query.
    final double recency = math.max(0.4, 1.0 - (i * 0.15));

    double best = 0;
    for (final String word in _words(terms[i])) {
      best = math.max(
        best,
        _fieldScore(
          word: word,
          name: name,
          category: category,
          cuisines: cuisines,
          restaurantName: restaurantName,
          description: description,
        ),
      );
    }
    total += recency * best;
  }
  return math.min(total, 2.0);
}

/// Where the word was found, in descending order of how much it means.
///
/// A dish called "Chicken Biryani" is about biryani. A dish filed under Biryani,
/// or from a kitchen whose cuisine tag says Biryani, probably is. A dish whose
/// *description* happens to mention it — "goes well with our biryani" — barely
/// is, and scores accordingly rather than being thrown away.
double _fieldScore({
  required String word,
  required String name,
  required String category,
  required String cuisines,
  required String restaurantName,
  required String description,
}) {
  if (name.contains(word)) return 1.0;
  if (category.contains(word) || cuisines.contains(word)) return 0.6;
  if (restaurantName.contains(word)) return 0.45;
  if (description.contains(word)) return 0.3;
  return 0;
}

/// How good the dish is, independent of who is looking.
///
/// The dish's own rating when it has one, and the restaurant's when it does not
/// — an unrated dish at a 4.6 kitchen is a better guess than a hard zero, which
/// would bury every dish too new to have been rated. Bestseller is a separate
/// bump because it measures something ratings do not: how many people actually
/// ordered it.
double _quality(DishSuggestion dish) {
  final double dishRating = dish.item.rating ?? dish.restaurant.rating;
  return (dishRating / 5.0) * 0.8 +
      (dish.item.isBestseller ? 0.35 : 0.0) +
      (dish.restaurant.rating / 5.0) * 0.2;
}

/// A small, stable shuffle in [0, 0.45) — enough to reorder dishes that scored
/// within a rounding error of each other, never enough to promote a poor match.
///
/// FNV-1a over the id and the rotation, rather than `Random` or `Object.hash`,
/// because it has to give the same answer on every launch of the same day: a
/// rail that reshuffles each time Home is opened does not look curated, it looks
/// broken. A rotation of 0 means "no jitter at all".
double _jitter(String id, int rotation) {
  if (rotation == 0) return 0;

  int hash = 0x811c9dc5;
  for (final int unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  for (int r = rotation; r > 0; r ~/= 251) {
    hash = ((hash ^ (r % 251)) * 0x01000193) & 0x7fffffff;
  }
  return (hash % 1000) / 1000 * 0.45;
}

/// Words worth matching on. Anything under three letters is dropped — "of" and
/// "a" appear in half the menu, so matching them would score every dish equally
/// and turn the ranking back into noise.
Iterable<String> _words(String term) =>
    term.split(RegExp(r'\s+')).where((String w) => w.length >= 3);

String _normalize(String s) => s.trim().toLowerCase();
