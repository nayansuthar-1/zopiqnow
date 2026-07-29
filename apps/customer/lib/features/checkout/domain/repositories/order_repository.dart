import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Contract for coupons and order placement (SAD 7.4).
abstract interface class OrderRepository {
  /// Validates [code] against the cart's [subtotal].
  ///
  /// Throws [CouponFailure] with a human-readable reason when the code is
  /// unknown or the cart doesn't meet the coupon's minimum.
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  });

  /// Places the order and returns the receipt.
  ///
  /// Takes no bill. The order service prices the cart from its own menu and its
  /// own coupon rules, and the receipt it returns is the truth — what the
  /// checkout screen showed was only ever an estimate of it.
  ///
  /// [paymentId] is the gateway's reference for an already-paid order, and null
  /// for cash on delivery.
  ///
  /// Throws [OrderPlacementFailure] on any transport error, or with the
  /// service's own message when it rejects the order (a dish went unavailable,
  /// a coupon no longer applies).
  /// The buyer is whoever the session says they are — the order service reads it
  /// from the JWT, so there is no user id to pass. [userPhone] is the number the
  /// rider calls.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
    String? deliveryNotes,
  });

  /// Coupon codes to advertise on the checkout screen.
  Future<List<String>> getCouponHints();

  /// The signed-in customer's order history, newest first.
  ///
  /// Throws [OrdersLoadFailure] on any transport or contract error. A signed-out
  /// caller gets an empty list, not a failure: having no orders and having no
  /// account look the same from here, and the screen behind an auth guard will
  /// never ask.
  Future<List<CustomerOrder>> getOrders();

  /// One order, by id, or null when the customer has no such order.
  ///
  /// Throws [OrdersLoadFailure] on a transport error — which is a different
  /// thing from "no such order", and the detail screen says something different
  /// about each.
  Future<CustomerOrder?> getOrder(String orderId);

  /// The order's status, now and as the kitchen changes it.
  ///
  /// Errors are left on the stream rather than translated: the screen already
  /// holds the order, so a broken subscription costs it live updates, not the
  /// receipt. It falls back to the status it fetched.
  Stream<OrderStatus> watchOrderStatus(String orderId);

  /// The rider carrying this order, or null when there is nobody to name.
  ///
  /// Never throws. A rider is an addition to a tracking card that already says
  /// everything essential, so a failed read costs a name and a phone number —
  /// not the screen. Null on failure is indistinguishable from null because no
  /// one has picked the order up, and the card renders both the same way: by
  /// showing nothing.
  Future<OrderRider?> getRider(String orderId);

  /// The delivery code to read out at the door, or null when there is nothing
  /// to confirm yet. Never throws, for the same reason [getRider] does not.
  Future<String?> getDeliveryCode(String orderId);

  /// The two pins, the road between them and the live arrival time (0057), or
  /// null when there is nothing to draw. Never throws — a map is an addition to
  /// a tracking card that already says everything essential.
  Future<DeliveryRoute?> getRoute(String orderId);

  /// Where the rider is, live. See [OrderDataSource.watchRiderPosition] for what
  /// [carrierKey] is and, more importantly, what it is not.
  Stream<RiderPosition?> watchRiderPosition(String carrierKey);

  /// Calls the order off, while the order service still allows it.
  ///
  /// Throws [OrderCancelFailure] — always, on any failure, and with the
  /// service's own sentence when it has one. This is the opposite of [getRider]
  /// on purpose: a rider's name is a nicety, and a cancellation that quietly
  /// did nothing is a customer who believes their order has stopped.
  Future<void> cancelOrder({required String orderId, String? reason});

  /// The sentences this customer may send on a live order. Empty is a real
  /// answer and means the chat has nothing to offer — the sheet does not open.
  Future<List<CannedMessage>> getMessageMenu();

  /// The thread on an order, now and as either side adds to it.
  Stream<List<OrderMessage>> watchMessages(String orderId);

  /// Says one of [getMessageMenu]'s lines.
  ///
  /// Throws [OrderMessageFailure] — always, on any failure. The opposite of
  /// [getRider] on purpose: a message that quietly did not send is a customer
  /// standing at a window believing they have been told where to wait.
  Future<void> sendMessage({required String orderId, required String code});

  /// Marks the rider's lines seen. Never throws.
  Future<void> markMessagesRead(String orderId);
}

/// A message the order service refused, or one that never reached it.
/// [message] is written for the customer and the sheet shows it verbatim.
class OrderMessageFailure implements Exception {
  const OrderMessageFailure([
    this.message = 'We couldn\'t send that. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderMessageFailure: $message';
}

/// A cancellation the order service refused, or one that never reached it.
/// [message] is written for the customer — "The kitchen has already started
/// cooking this order." — and the screen shows it verbatim.
class OrderCancelFailure implements Exception {
  const OrderCancelFailure([
    this.message = 'We couldn\'t cancel that order. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderCancelFailure: $message';
}

/// Domain-level failure for reading order history.
class OrdersLoadFailure implements Exception {
  const OrdersLoadFailure([
    this.message = 'We couldn\'t load your orders. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrdersLoadFailure: $message';
}

/// A coupon the order service rejected. [message] is written for the customer,
/// not the log — the checkout screen renders it under the coupon field.
class CouponFailure implements Exception {
  const CouponFailure(this.message);

  final String message;

  @override
  String toString() => 'CouponFailure: $message';
}

/// Domain-level failure for order placement.
class OrderPlacementFailure implements Exception {
  const OrderPlacementFailure([
    this.message = 'We couldn\'t place your order. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderPlacementFailure: $message';
}
