import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';

/// The Gifts catalog read contract, implemented by Supabase. This interface is
/// what would make a backend swap a one-line provider change, and what lets
/// tests inject a fake without a network.
abstract interface class GiftDataSource {
  Future<List<GiftShop>> fetchShops();

  Future<List<GiftItem>> fetchItems();

  /// Null when no shop carries [id]. The repository maps that to a domain-level
  /// not-found, which is not the same thing as a transport error.
  Future<GiftShop?> fetchShopById(String id);

  Future<List<GiftItem>> fetchItemsByShop(String shopId);
}
