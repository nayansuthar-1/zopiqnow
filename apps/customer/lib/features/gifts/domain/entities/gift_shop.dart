import 'package:flutter/foundation.dart';

/// A dedicated gift seller — not a restaurant. Shown as a storefront on the
/// customer Gifts tab.
///
/// Pure domain entity: no JSON, no Flutter. The data layer maps rows into this;
/// the UI reads only this (repository pattern, mirroring [Restaurant]).
@immutable
class GiftShop {
  const GiftShop({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.imageUrl,
    required this.rating,
    required this.ratingCount,
  });

  final String id;
  final String name;

  /// One-line pitch under the name ("Handcrafted homeware & decor").
  final String tagline;
  final String description;

  /// Remote cover URL. Empty when the seller never uploaded one — the UI falls
  /// back to the same branded gradient placeholder restaurants use.
  final String imageUrl;

  /// Null when the shop has too few ratings to show one. Not 0 — "unrated" and
  /// "rated zero" are different claims.
  final double? rating;
  final int ratingCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GiftShop && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
