/// Which dishes belong to a home category tile.
///
/// Tapping a tile used to run `String.contains` over the dish name, the menu
/// section **and the kitchen's cuisine tags**, and all three parts of that were
/// wrong on the real catalogue:
///
///  * `"Classic Cakes".contains("lassi")` is true — C-***lassi***-c — so the
///    Lassi tile opened on a page of cakes.
///  * `"Shakes & Beverages".contains("shake")` is true of every dish filed in
///    that section, so the Shake tile served "Shiv Special Lassi".
///  * Sadri Restaurent tags itself *Burgers*, so its Dal Fry and Jeera Rice were
///    burgers.
///
/// So matching is by whole word here, a dish's own name outranks the section it
/// is filed under, and cuisine tags describe kitchens rather than dishes.
library;

import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// Everything [category] is searched by: its label first, then any spelling a
/// menu in the wild uses for the same food.
List<String> categoryTerms(FoodCategory category) => <String>[
  category.label,
  ...category.aliases,
];

/// [term] reduced to the form both the server query and [hasTerm] match on.
///
/// Lowercased and stripped of one trailing `s`, so a plural tile ("Momos",
/// "Fries") still finds the singular a menu wrote ("Steam Momo"). [hasTerm] puts
/// the ending back as optional, so nothing is lost in the other direction.
String categoryNeedle(String term) {
  final String lower = term.trim().toLowerCase();
  return lower.endsWith('s')
      ? lower.substring(0, lower.length - 1)
      : lower;
}

/// Whether [text] uses [term] as a word rather than as a run of letters inside
/// one.
///
/// The match has to *end* on a word boundary; it does not have to start on one.
/// That asymmetry is the whole rule, and both halves of it are load-bearing:
///
///  * demanding the end rejects "**Classi**c Cakes" for "lassi" and "**Frie**d
///    Momos" for "fries", which is what put cakes under Lassi;
///  * allowing a run-on start accepts "Milk**shake**s" for "shake" and
///    "Cheezy Masala **Maggi**e" for "maggi", which real menus write as one
///    word.
///
/// A short vowel-or-plural tail is still a word end, which is what "Maggie",
/// "Cakes" and "Momos" need.
bool hasTerm(String text, String term) {
  final String haystack = text.toLowerCase();
  final String needle = categoryNeedle(term);
  if (needle.isEmpty) return false;

  for (int from = 0; from <= haystack.length - needle.length;) {
    final int at = haystack.indexOf(needle, from);
    if (at < 0) return false;
    if (_endsWord(haystack, at + needle.length)) return true;
    from = at + 1;
  }
  return false;
}

/// True when at most an `e`, an `s` or `es` stands between [at] and the end of
/// the word.
bool _endsWord(String haystack, int at) {
  int i = at;
  if (i < haystack.length && haystack[i] == 'e') i++;
  if (i < haystack.length && haystack[i] == 's') i++;
  return i == haystack.length || !_isLetter(haystack.codeUnitAt(i));
}

bool _isLetter(int unit) =>
    (unit >= 0x61 && unit <= 0x7a) || (unit >= 0x41 && unit <= 0x5a);

/// The dishes in [pool] that belong to [category].
///
/// [vocabulary] is every tile the app ships, unfiltered — see
/// [_claimedByAnother] for what it is read for. Passing it in rather than
/// reaching for a global is what keeps this function pure and testable.
List<DishSuggestion> dishesInCategory(
  List<DishSuggestion> pool,
  FoodCategory category,
  List<FoodCategory> vocabulary,
) => pool
    .where((DishSuggestion d) => dishMatchesCategory(d, category, vocabulary))
    .toList(growable: false);

bool dishMatchesCategory(
  DishSuggestion dish,
  FoodCategory category,
  List<FoodCategory> vocabulary,
) => namedDishMatchesCategory(
  name: dish.item.name,
  section: dish.category,
  category: category,
  vocabulary: vocabulary,
);

/// The matching rule itself, over the only two things it has ever read: the
/// dish's name and the menu section it sits in.
///
/// Extracted from [dishMatchesCategory] so that a caller holding those two
/// strings and nothing else can ask the same question. That caller is
/// `orderByPopularity`, which buckets sold order lines into tiles — an
/// `order_items` row carries a frozen name and no `MenuItem` at all, and
/// building a fake [DishSuggestion] to satisfy a signature would have meant a
/// second copy of this rule, free to drift from this one. There is one rule and
/// two ways in.
bool namedDishMatchesCategory({
  required String name,
  required String section,
  required FoodCategory category,
  required List<FoodCategory> vocabulary,
}) {
  final List<String> terms = categoryTerms(category);
  final bool inSection = terms.any((String t) => hasTerm(section, t));

  // A cuisine is not a property of a dish's name — a kitchen filing something
  // under "Chinese Spl." is the only claim being made, and its pizzas are not
  // Chinese just because it also cooks Chinese food.
  if (category.kind == FoodCategoryKind.cuisine) return inSection;

  if (terms.any((String t) => hasTerm(name, t))) return true;
  return inSection && !_nameClaimedByAnother(name, category, vocabulary);
}

/// Whether the dish's own name names some *other* tile.
///
/// This is what a section match yields to. Sections are mixed bags — Shiv files
/// "Shiv Special Lassi" and "Cold Coffee" under *Shakes & Beverages*, and
/// Purohitji files "Veg Pulao" under *Rice* — and in every one of those the
/// dish's name is the more specific truth. So the section places a dish only
/// when its name has not already placed it somewhere else.
///
/// Cuisine tiles are skipped: their sections are what the dishes inside them are
/// *for*, so a dosa filed under "South Indian" must stay there even though the
/// Dosa tile also claims it.
bool _nameClaimedByAnother(
  String name,
  FoodCategory category,
  List<FoodCategory> vocabulary,
) => vocabulary.any(
  (FoodCategory other) =>
      other.kind == FoodCategoryKind.dish &&
      other.id != category.id &&
      categoryTerms(other).any((String t) => hasTerm(name, t)),
);
