import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';

/// Contract for reading the Gifts catalog. The presentation layer depends only
/// on this abstraction; the concrete implementation (Supabase) is bound via
/// Riverpod, exactly like [RestaurantRepository].
abstract interface class GiftRepository {
  /// Every active gift shop, for the storefront rail.
  ///
  /// Throws [GiftLoadFailure] on any transport/parse error.
  Future<List<GiftShop>> getShops();

  /// Every available gift item across all shops, ordered for browsing.
  ///
  /// Throws [GiftLoadFailure] on any transport/parse error.
  Future<List<GiftItem>> getItems();

  /// A single shop by id, for its storefront page.
  ///
  /// Throws [GiftShopNotFound] when no such shop exists, and [GiftLoadFailure]
  /// on any transport/parse error.
  Future<GiftShop> getShopById(String id);

  /// The available items of one shop, ordered by shelf then rank.
  ///
  /// Throws [GiftLoadFailure] on any transport/parse error.
  Future<List<GiftItem>> getItemsByShop(String shopId);
}

/// The requested shop does not exist — a stale link, or a seller that has since
/// left the platform. Distinct from [GiftLoadFailure]: retrying will never help.
class GiftShopNotFound implements Exception {
  const GiftShopNotFound([
    this.message = 'This gift shop is no longer available.',
  ]);

  final String message;

  @override
  String toString() => 'GiftShopNotFound: $message';
}

/// Domain-level failure for the Gifts catalog. Keeps Flutter/HTTP details out of
/// the UI, which only needs a human message and the fact that it is retryable.
class GiftLoadFailure implements Exception {
  const GiftLoadFailure([this.message = 'We couldn\'t load gifts right now.']);

  final String message;

  @override
  String toString() => 'GiftLoadFailure: $message';
}
