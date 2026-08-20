import 'package:flutter/foundation.dart';

/// What a category tile groups by, which decides how a dish is tested against
/// it.
///
/// The two are not the same question. "Dosa" is a thing on a plate, so a dish is
/// a dosa when its own name or its menu section says so. "Chinese" is a thing
/// about a kitchen, so a dish is Chinese when the menu files it under Chinese —
/// and a restaurant is Chinese when it says it is, whatever it happens to cook.
enum FoodCategoryKind { dish, cuisine }

/// A dish category in the Home "What's on your mind?" rail.
///
/// Pure domain — no Flutter widgets, no icons. [imageAsset] is the single seam
/// for artwork: while it is null the UI draws generated placeholder art. Drop in
/// licensed illustrations, set this field, and the rail switches over with no
/// layout change.
@immutable
class FoodCategory {
  const FoodCategory({
    required this.id,
    required this.label,
    this.imageAsset,
    this.isVeg = true,
    this.kind = FoodCategoryKind.dish,
    this.aliases = const <String>[],
  });

  final String id;

  /// Display copy under the tile, e.g. "Biryani". Also the primary matching
  /// term — see `category_matching.dart`.
  final String label;

  /// Bundled asset path, e.g. `assets/categories/biryani.webp`. Null until real
  /// artwork is supplied.
  final String? imageAsset;

  /// False for meat and egg dishes. "100% Veg Mode" hides those tiles, so the
  /// mode is honoured before a tap rather than after — a person who has turned
  /// meat off should not be shown a Mutton tile at all.
  final bool isVeg;

  final FoodCategoryKind kind;

  /// Other spellings the same food goes by on a real menu.
  ///
  /// Menus are typed by the kitchen, not by us: Wing Orbit sells "Chola
  /// Bhatura" and Purohitji sells "Paneer Pakoda", so tiles labelled "Chole
  /// Bhature" and "Pakode" match nothing at all without these. Only add a term
  /// a menu actually uses — every alias widens what the tile catches.
  final List<String> aliases;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FoodCategory && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
