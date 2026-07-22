import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// The order contract, implemented by the mock and by Supabase.
///
/// Note what is *absent*: no prices. [placeOrder] sends dish ids and quantities
/// and the order service prices them. The client cannot quote a total even if it
/// wanted to, and a client that cannot quote a total cannot get one wrong.
abstract interface class OrderDataSource {
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  });

  /// No user id: `place_order` reads it from the caller's JWT (`auth.uid()`).
  /// A client that could name the buyer could buy in someone else's name.
  /// [userPhone] is a delivery contact, not an identity.
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
  });

  /// Codes to advertise on the checkout screen, e.g. `WELCOME50 · ₹50 off`.
  /// Advertising a coupon is not honouring one — that is `applyCoupon`'s job.
  Future<List<String>> fetchCouponHints();

  /// The signed-in customer's orders, newest first.
  ///
  /// No user id here either, and for the same reason: the caller does not say
  /// whose orders it wants. `auth.uid()` does, through the row-level policy on
  /// `orders` — a client that could name the buyer could read someone else's
  /// receipts, which carry a phone number and a home address.
  Future<List<CustomerOrder>> fetchOrders();

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
  Stream<OrderStatus> watchOrderStatus(String orderId);

  /// Who is carrying the order, or null when nobody is.
  ///
  /// Null is the ordinary answer and not an edge case: no rider has taken the
  /// job yet, or one has but is still at the counter, or the order arrived and
  /// the delivery is over. All three look the same from here — and they should,
  /// because in all three there is no one to name.
  Future<OrderRider?> fetchRider(String orderId);
}
