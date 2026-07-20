import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';

/// The `gift_shops` columns every query selects, and the one place a row of them
/// becomes a [GiftShop]. Kept together so a new column is added in exactly one
/// place.
const String giftShopColumns =
    'id, name, tagline, description, image_url, rating, rating_count';

/// The `gift_items` columns every query selects, and the one place a row of them
/// becomes a [GiftItem].
const String giftItemColumns =
    'id, shop_id, name, description, price, image_url, image_urls, category, '
    'category_rank, item_rank';

/// Postgres row → domain entity. Numeric columns arrive as `num`, so each is
/// coerced explicitly.
GiftShop giftShopFromRow(Map<String, dynamic> row) => GiftShop(
  id: row['id'] as String,
  name: row['name'] as String,
  tagline: row['tagline'] as String? ?? '',
  description: row['description'] as String? ?? '',
  imageUrl: row['image_url'] as String? ?? '',
  // Null stays null — the shop is unrated, not rated zero.
  rating: (row['rating'] as num?)?.toDouble(),
  ratingCount: (row['rating_count'] as num?)?.toInt() ?? 0,
);

GiftItem giftItemFromRow(Map<String, dynamic> row) => GiftItem(
  id: row['id'] as String,
  shopId: row['shop_id'] as String,
  name: row['name'] as String,
  description: row['description'] as String? ?? '',
  price: (row['price'] as num).toInt(),
  imageUrl: row['image_url'] as String? ?? '',
  // Postgres text[] arrives as a List<dynamic>; null on a row written before the
  // column existed. Empty stays empty — the detail screen falls back to the
  // single image.
  imageUrls:
      (row['image_urls'] as List<dynamic>?)?.cast<String>() ??
      const <String>[],
  category: row['category'] as String,
  categoryRank: (row['category_rank'] as num?)?.toInt() ?? 0,
  itemRank: (row['item_rank'] as num?)?.toInt() ?? 0,
);
