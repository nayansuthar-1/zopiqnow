import 'package:flutter/foundation.dart';

/// A dish category in the Home "What's on your mind?" rail.
///
/// Pure domain — no Flutter widgets, no icons. [imageAsset] is the single seam
/// for artwork: while it is null the UI draws generated placeholder art. Drop in
/// licensed illustrations, set this field, and the rail switches over with no
/// layout change.
@immutable
class FoodCategory {
  const FoodCategory({required this.id, required this.label, this.imageAsset});

  final String id;

  /// Display copy under the tile, e.g. "Biryani".
  final String label;

  /// Bundled asset path, e.g. `assets/categories/biryani.webp`. Null until real
  /// artwork is supplied.
  final String? imageAsset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FoodCategory && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
