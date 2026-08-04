import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
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

/// The gift *ordering* contract (migration 0096), beside the catalogue read
/// above. Separate methods rather than a separate interface because the shop
/// page, the bag and the receipt are one feature and one Supabase client.
abstract interface class GiftOrderDataSource {
  /// Places the order and returns the receipt. Takes no prices — ids and
  /// quantities only, and `place_gift_order` prices them.
  ///
  /// [idempotencyKey] is one value per checkout attempt, reused on every retry
  /// of that attempt: the service answers a key it has seen with the order it
  /// already placed rather than buying the gift twice.
  Future<GiftOrder> placeOrder({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String userPhone,
    required String deliveryTo,
    String? deliveryNotes,
    String? paymentId,
    String? idempotencyKey,
  });

  /// This customer's gift orders, newest first.
  Future<List<GiftOrder>> fetchOrders();

  /// The lines on one of their own orders.
  Future<List<GiftOrderLine>> fetchOrderLines(String orderId);

  /// Calls one off, while it is still callable off. Throws [GiftOrderFailure]
  /// with the service's own sentence when it is not.
  Future<void> cancelOrder({required String orderId, String? reason});
}
