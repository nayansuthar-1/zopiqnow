import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// A dish, plus the kitchen that cooks it.
///
/// Home and Search both show dishes across restaurants now, and a [MenuItem] on
/// its own cannot render one: the card names the restaurant, the ADD control
/// needs its id and name to build a cart line, and a paused kitchen greys the
/// button out. So the join happens once — in `dishPoolProvider` — and the pair
/// travels together from there rather than every widget looking a restaurant up
/// by id.
@immutable
class DishSuggestion {
  const DishSuggestion({
    required this.item,
    required this.restaurant,
    required this.category,
  });

  final MenuItem item;
  final Restaurant restaurant;

  /// The menu section the dish sits in — "Biryani", "Desserts".
  ///
  /// Not a field on [MenuItem] because the menu screen learns it from the
  /// section heading the dish is under. Here it is a ranking signal: somebody
  /// who searched "biryani" should reach a dish filed under Biryani even when
  /// its own name never says the word ("Paradise Special, Family Pack").
  final String category;

  /// Two dishes are the same dish when they are the same row. The restaurant is
  /// a consequence of the dish, not part of its identity.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DishSuggestion && other.item.id == item.id);

  @override
  int get hashCode => item.id.hashCode;
}
