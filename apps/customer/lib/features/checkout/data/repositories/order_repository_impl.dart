import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Default [OrderRepository]. Names the data source interface, so the mock and
/// Postgres are interchangeable.
class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this._dataSource);

  final OrderDataSource _dataSource;

  @override
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  }) {
    // CouponFailure passes through untouched — it *is* the domain answer.
    return _dataSource.applyCoupon(code: code, subtotal: subtotal);
  }

  @override
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userId,
    required String userPhone,
    String? couponCode,
    String? paymentId,
  }) async {
    try {
      return await _dataSource.placeOrder(
        cart: cart,
        deliveryAddress: deliveryAddress,
        paymentMethod: paymentMethod,
        userId: userId,
        userPhone: userPhone,
        couponCode: couponCode,
        paymentId: paymentId,
      );
    } on OrderPlacementFailure {
      // Already a domain failure carrying the service's own message — relabelling
      // it as a generic error would throw away the only useful sentence in it.
      rethrow;
    } on CouponFailure catch (failure) {
      // The coupon was valid when applied and is not valid now — the cart moved
      // under it. That is a *placement* failure at this point (the screen has no
      // coupon field to attach an error to any more), but the reason is worth
      // keeping: "Add items worth ₹99 more" tells the customer what to do, and
      // "please try again" tells them nothing.
      throw OrderPlacementFailure(failure.message);
    } on Object catch (_) {
      throw const OrderPlacementFailure();
    }
  }

  @override
  Future<List<String>> getCouponHints() async {
    try {
      return await _dataSource.fetchCouponHints();
    } on Object catch (_) {
      // A missing hint is a missing hint. Checkout still works without it, so
      // this must never take the screen down.
      return const <String>[];
    }
  }
}
