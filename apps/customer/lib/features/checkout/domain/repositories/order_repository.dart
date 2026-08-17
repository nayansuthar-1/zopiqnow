import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/delivery_surcharge.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Contract for coupons and order placement (SAD 7.4).
abstract interface class OrderRepository {
  /// Validates [code] against the cart's [subtotal] at [restaurantId].
  ///
  /// Throws [CouponFailure] with a human-readable reason when the code is
  /// unknown, out of scope for this kitchen, or the cart doesn't meet the
  /// coupon's minimum. A code belonging to another restaurant is refused with
  /// the same sentence as one that does not exist — deliberately, so this is
  /// not a way to enumerate other kitchens' promotions.
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
    required String restaurantId,
  });

  /// Everything [placeOrder] could refuse on, asked before any money moves, and
  /// the total the gateway should be asked for (migration 0120).
  ///
  /// Exists because the order of operations is charge-then-place: without this,
  /// a kitchen that closed while the cart sat open costs the customer a payment
  /// and buys them nothing, and there is no order for the refund machinery to
  /// attach itself to.
  ///
  /// Throws [OrderPlacementFailure] with the service's own sentence. Callers
  /// should let it propagate exactly as they would from [placeOrder] — it is the
  /// same refusal, arriving early enough to be free.
  Future<int> preflight({
    required Cart cart,
    required Address deliveryAddress,
    String? couponCode,
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
  /// [idempotencyKey] is one value per checkout attempt, reused on every retry
  /// of that attempt. A key the service has already seen is answered with the
  /// order it already placed (migration 0086), which is what makes a lost
  /// response safe to retry.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
    String? deliveryNotes,
    String? idempotencyKey,
  });

  /// The offers a cart from [restaurantId] can use — Zopiqnow's own plus that
  /// kitchen's. Never throws: checkout works without a hint, so a failed read
  /// is an empty list, not a broken screen.
  Future<List<RestaurantOffer>> getOffers(String restaurantId);

  /// What the hour and the weather are adding to delivery at [restaurantId]
  /// (migration 0129). Never throws: a bill that cannot read the surcharge
  /// quotes the plain fee, and the amount actually charged comes from
  /// `checkout_preflight` at the moment of payment either way.
  Future<DeliverySurcharge> getDeliverySurcharge(String restaurantId);

  /// The signed-in customer's order history, newest first.
  ///
  /// Throws [OrdersLoadFailure] on any transport or contract error. A signed-out
  /// caller gets an empty list, not a failure: having no orders and having no
  /// account look the same from here, and the screen behind an auth guard will
  /// never ask.
  ///
  /// A page shorter than [limit] is the end of the history — there is no count,
  /// deliberately.
  Future<List<CustomerOrder>> getOrders({int offset = 0, int limit = 25});

  /// One order, by id, or null when the customer has no such order.
  ///
  /// Throws [OrdersLoadFailure] on a transport error — which is a different
  /// thing from "no such order", and the detail screen says something different
  /// about each.
  Future<CustomerOrder?> getOrder(String orderId);

  /// The order's status and its arrival time, now and as they change.
  ///
  /// Errors are left on the stream rather than translated: the screen already
  /// holds the order, so a broken subscription costs it live updates, not the
  /// receipt. It falls back to the status it fetched.
  Stream<OrderProgress> watchOrderProgress(String orderId);

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

  /// Whether this order can be reviewed, and whether anyone carried it. Never
  /// throws: a receipt that cannot answer simply shows no rating prompt, which
  /// is what an un-reviewable order shows anyway.
  Future<OrderReviewState> getReviewState(String orderId);

  /// What this customer already said about the order, or null. Never throws,
  /// for the reason [getReviewState] does not.
  Future<OrderReview?> getMyReview(String orderId);

  /// Money going back on this order, oldest first, and empty for almost every
  /// order. Never throws: a read that failed shows no refund line, which is what
  /// the overwhelming majority of receipts show anyway.
  Future<List<OrderRefund>> getRefunds(String orderId);

  /// What this customer has already reported about the order (0095). Empty on
  /// any failure, like [getRefunds]: a complaint list that could not load must
  /// not take the receipt down with it.
  Future<List<OrderIssue>> getIssues(String orderId);

  /// Reports a problem. Rethrows [OrderIssueFailure] — unlike the reads above,
  /// this one is a thing the customer just did, and it has to say whether it
  /// worked.
  Future<void> raiseIssue({
    required String orderId,
    required IssueCategory category,
    String? body,
  });

  /// Rates the food, and optionally the rider.
  ///
  /// Throws [OrderReviewFailure] — always, on any failure. The opposite of
  /// [getRider] on purpose: a rating that quietly did not save is a customer
  /// who believes they have been heard.
  Future<void> submitReview({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  });

  /// The tax invoice for a delivered order. Throws [InvoiceFailure] with the
  /// service's sentence — a document is the whole point of the screen, so
  /// there is nothing to degrade to.
  Future<OrderInvoice> getInvoice(String orderId);
}

/// A review the order service refused, or one that never reached it.
/// [message] is written for the customer and the sheet shows it verbatim.
class OrderReviewFailure implements Exception {
  const OrderReviewFailure([
    this.message = 'We couldn\'t save your review. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderReviewFailure: $message';
}

/// An invoice that could not be produced. [message] is the service's own
/// sentence when it has one — "An invoice is issued once your order has been
/// delivered." — and the screen shows it verbatim.
class InvoiceFailure implements Exception {
  const InvoiceFailure([
    this.message = 'We couldn\'t load this invoice. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'InvoiceFailure: $message';
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
