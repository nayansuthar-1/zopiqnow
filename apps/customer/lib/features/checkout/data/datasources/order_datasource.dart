import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
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

  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userId,
    required String userPhone,
    String? couponCode,
    String? paymentId,
  });

  /// Codes to advertise on the checkout screen, e.g. `WELCOME50 · ₹50 off`.
  /// Advertising a coupon is not honouring one — that is `applyCoupon`'s job.
  Future<List<String>> fetchCouponHints();
}
