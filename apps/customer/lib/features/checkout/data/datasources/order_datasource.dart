import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
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
}
