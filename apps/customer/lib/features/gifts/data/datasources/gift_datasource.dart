// A complaint is a complaint whichever kind of order it is about, so gifts
// reuse the checkout feature's entity rather than declaring a parallel one that
// would have to be kept identical by hand.
import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
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
  /// What this bag costs, priced by the service (`gift_bag_quote`, 0112).
  ///
  /// Called before the gateway is opened, because the amount charged has to be
  /// the amount the order records and only the service knows the tax. Throws
  /// [GiftOrderFailure] with the service's own sentence when something in the
  /// bag can no longer be bought — which is the same sentence placing it would
  /// have produced, one screen earlier.
  Future<GiftQuote> quoteBag({
    required String shopId,
    required List<Map<String, dynamic>> items,
  });

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

  // No `cancelOrder`. A gift order is final once it is placed (0116) — the
  // database refuses it with a sentence for builds that still have the button,
  // and this app no longer has one to press.

  /// Complaints this customer has already raised about one of their own gift
  /// orders (0114). Empty for almost every order.
  ///
  /// The only route a customer has back into this system on a gift, now that
  /// there is no cancel and no refund.
  Future<List<OrderIssue>> fetchIssues(String orderId);

  /// Reports a problem with a gift order. Throws [OrderIssueFailure] carrying
  /// the service's own sentence — "You have already reported this order." — so
  /// the sheet can print it rather than a generic apology.
  ///
  /// Raising one moves no money and changes no status; it lands in the support
  /// queue an admin works.
  Future<void> raiseIssue({
    required String orderId,
    required IssueCategory category,
    String? body,
  });
}
