import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
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

/// The order contract, implemented by the mock and by Supabase.
///
/// Note what is *absent*: no prices. [placeOrder] sends dish ids and quantities
/// and the order service prices them. The client cannot quote a total even if it
/// wanted to, and a client that cannot quote a total cannot get one wrong.
abstract interface class OrderDataSource {
  /// Validates [code] against a cart of [subtotal] at [restaurantId].
  ///
  /// [restaurantId] is not optional and not decoration: since migration 0064 a
  /// coupon may belong to one kitchen, and `validate_coupon` refuses a code that
  /// is not in scope. Omitting it defaults the argument to null server-side,
  /// which matches platform coupons *only* — so every restaurant's own offer,
  /// advertised on its own checkout screen, was answered "This code isn't
  /// valid." The scope has to travel with the code from here.
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
    required String restaurantId,
  });

  /// Asks every question [placeOrder] would refuse on, *before* the gateway is
  /// opened, and returns the total to charge (migration 0120).
  ///
  /// The gateway runs first and `place_order` runs second, so any rule that
  /// fires at insert — a kitchen that shut, a dish that sold out, a coupon that
  /// expired, an account over its hourly limit — refuses an order the customer
  /// has already paid for, and no refund is recorded because there is no order
  /// to hang one on. This asks all of it up front instead.
  ///
  /// The returned number is the *server's* total, not the cart's. They should
  /// agree, and the point is what happens when they do not: the payment gate
  /// refuses an intent worth less than the order, so charging the phone's figure
  /// and letting Postgres price the order is itself a charge-then-refuse. Charge
  /// this.
  ///
  /// Advisory by construction. It takes no locks and writes nothing, so a cart
  /// can still go stale in the seconds the payment sheet is open; `place_order`
  /// re-checks and re-prices everything and remains the only authority.
  ///
  /// Throws [OrderPlacementFailure] carrying the service's own sentence — the
  /// same sentence [placeOrder] would have thrown after taking the money.
  Future<int> preflight({
    required Cart cart,
    required Address deliveryAddress,
    String? couponCode,
  });

  /// No user id: `place_order` reads it from the caller's JWT (`auth.uid()`).
  /// A client that could name the buyer could buy in someone else's name.
  /// [userPhone] is a delivery contact, not an identity.
  ///
  /// [deliveryNotes] is the customer's sentence about their own front door, and
  /// is frozen onto the order rather than read back off the address later —
  /// editing "ring twice" into "the bell is broken" must not rewrite what the
  /// rider was told last Tuesday.
  /// [idempotencyKey] makes a retry safe. One key per checkout attempt, reused
  /// verbatim on every retry of that attempt: the service answers a key it has
  /// already seen with the order it already placed, rather than placing a
  /// second one (migration 0086). Null is allowed and means "no protection" —
  /// which is what every caller had before C4.
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

  /// The offers a cart from [restaurantId] can actually use: Zopiqnow's own,
  /// plus that kitchen's (migration 0064). Advertising a coupon is not
  /// honouring one — that is `applyCoupon`'s job, and it re-checks the scope.
  Future<List<RestaurantOffer>> fetchOffers(String restaurantId);

  /// The signed-in customer's orders, newest first, one page at a time.
  ///
  /// No user id here either, and for the same reason: the caller does not say
  /// whose orders it wants. `auth.uid()` does, through the row-level policy on
  /// `orders` — a client that could name the buyer could read someone else's
  /// receipts, which carry a phone number and a home address.
  ///
  /// A short page means there is nothing after it. That is the only end-of-list
  /// signal, and it is deliberately not a count: `count: exact` on a
  /// policy-filtered table costs a second scan on every page to answer a
  /// question the screen does not ask.
  Future<List<CustomerOrder>> fetchOrders({int offset = 0, int limit = 25});

  /// One order, by id. Null when there is no such order *or* it belongs to
  /// someone else — from here those are the same answer, and they should be:
  /// an id that says "this order exists, but not for you" is an id worth
  /// guessing at.
  Future<CustomerOrder?> fetchOrder(String orderId);

  /// The order's status, now and as it changes.
  ///
  /// Emits the current status on subscribe, so a caller never has to seed it,
  /// and again on every write to the row. The same row-level policy answers
  /// "whose?" here as everywhere else — a subscription is a select that stays
  /// open, and it is filtered by exactly the rule that filters one.
  Stream<OrderProgress> watchOrderProgress(String orderId);

  /// Who is carrying the order, or null when nobody is.
  ///
  /// Null is the ordinary answer and not an edge case: no rider has taken the
  /// job yet, or one has but is still at the counter, or the order arrived and
  /// the delivery is over. All three look the same from here — and they should,
  /// because in all three there is no one to name.
  Future<OrderRider?> fetchRider(String orderId);

  /// The four digits the rider must be told at the door, or null while there is
  /// nothing to confirm. Same shape as [fetchRider] and for the same reason.
  Future<String?> fetchDeliveryCode(String orderId);

  /// Both ends of the ride, the road between them, and the live arrival time
  /// (migration 0057). Null when the order has no delivery coordinates, which
  /// is the one case there is nothing to draw.
  ///
  /// Fetched rather than streamed: the two pins and the road never change, and
  /// the ETA changes on events the *status* stream already reports.
  Future<DeliveryRoute?> fetchRoute(String orderId);

  /// The rider's position, live, for as long as the food is on their bike.
  ///
  /// [carrierKey] is the delivery's `partner_email`, which the customer may
  /// already read off their own live delivery row (0039). It is a subscription
  /// filter and nothing else — it is never rendered, and the *permission* to see
  /// the position comes from the policy in 0057, not from holding this string.
  ///
  /// Emits null when the platform has no current fix: the rider has not started
  /// reporting, the app was killed, or the job ended and the row was purged.
  Stream<RiderPosition?> watchRiderPosition(String carrierKey);

  /// Calls the order off. No user id, for the reason [placeOrder] gives.
  ///
  /// [reason] is the customer's own words, stored on the order and read by the
  /// kitchen too — so it is written third-person or not at all.
  ///
  /// Throws [OrderCancelFailure] with the service's own sentence when the order
  /// has moved past the point of calling off. That sentence is the *answer*, not
  /// an error to bury: it says whether the food is being cooked, packed, or
  /// already on a bike.
  Future<void> cancelOrder({required String orderId, String? reason});

  /// The sentences this customer may send, in the order to show them.
  ///
  /// Fetched, not hard-coded: migration 0061 owns the wording, so what a button
  /// says is exactly what will be stored. The list is a constant on the server
  /// and changes only when a migration changes it, so one call per thread is
  /// the whole cost.
  Future<List<CannedMessage>> fetchMessageMenu();

  /// The thread on an order, now and as either side adds to it.
  ///
  /// A subscription rather than a poll for the reason the status stream is one:
  /// the interesting moment is a rider answering while the customer is looking
  /// at the screen. RLS filters it — the socket carries this order's thread
  /// because the policy says so, not because of the `.eq` that shapes it.
  Stream<List<OrderMessage>> watchMessages(String orderId);

  /// Says one of [fetchMessageMenu]'s lines.
  ///
  /// Throws [OrderMessageFailure] with the service's own sentence when it
  /// refuses — "There is nobody on this order to message right now." is the
  /// answer when the rider has just handed the food over, and it is worth
  /// showing verbatim.
  Future<void> sendMessage({required String orderId, required String code});

  /// Marks the rider's lines seen. Never throws: a read receipt that failed to
  /// register is not worth interrupting a conversation for.
  Future<void> markMessagesRead(String orderId);

  /// Whether this order can be reviewed, and whether anyone carried it
  /// (migration 0062). The three rules behind "can" — delivered, mine, inside
  /// the fortnight — are answered by the database, not re-implemented here.
  Future<OrderReviewState> fetchReviewState(String orderId);

  /// What this customer already said about the order, or null if nothing yet.
  Future<OrderReview?> fetchMyReview(String orderId);

  /// Money going back on this order (migration 0077), oldest first.
  ///
  /// Empty for almost every order, and empty is the answer for a cash order that
  /// was cancelled — nothing was collected, so nothing goes back.
  Future<List<OrderRefund>> fetchRefunds(String orderId);

  /// Rates the food, and optionally the rider who brought it.
  ///
  /// Idempotent by order: a second call inside the edit window replaces the
  /// first, and one after it is refused by the row itself. Throws
  /// [OrderReviewFailure] with the service's own sentence — "This review can no
  /// longer be changed." is the answer, not an error to bury.
  Future<void> submitReview({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  });

  /// The tax invoice for a delivered order (migration 0063).
  ///
  /// Throws [InvoiceFailure] with the service's sentence when there is no
  /// document yet — an invoice is issued on delivery, and "your order hasn't
  /// arrived" is a better answer than an empty page.
  Future<OrderInvoice> fetchInvoice(String orderId);

  /// What this customer has already reported about the order, newest first
  /// (migration 0095). Empty for almost every order.
  Future<List<OrderIssue>> fetchIssues(String orderId);

  /// Reports a problem with the order. Moves no money and changes no status —
  /// it lands in the support queue and somebody reads it.
  ///
  /// Throws [OrderIssueFailure] with the service's own sentence when it is
  /// refused: three per order and ten an hour are the caps, and both refusals
  /// are written for the customer to read.
  Future<void> raiseIssue({
    required String orderId,
    required IssueCategory category,
    String? body,
  });
}
