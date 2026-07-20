import 'package:flutter/foundation.dart';

/// A single giftable product — pottery, a candle, a personalised mug. Belongs to
/// one [GiftShop].
///
/// Pure domain entity. Price is whole rupees, the same unit menu items use.
@immutable
class GiftItem {
  const GiftItem({
    required this.id,
    required this.shopId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.category,
    required this.categoryRank,
    required this.itemRank,
  });

  final String id;
  final String shopId;
  final String name;
  final String description;

  /// Whole rupees.
  final int price;

  /// Remote image URL. Empty falls back to the branded gradient placeholder.
  final String imageUrl;

  /// The shelf this sits on ("Home Decor", "Candles & Fragrance"). [categoryRank]
  /// orders the shelves, [itemRank] orders products within one.
  final String category;
  final int categoryRank;
  final int itemRank;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GiftItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
