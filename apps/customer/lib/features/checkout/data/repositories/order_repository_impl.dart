import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
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
    required String userPhone,
    String? couponCode,
    String? paymentId,
  }) async {
    try {
      return await _dataSource.placeOrder(
        cart: cart,
        deliveryAddress: deliveryAddress,
        paymentMethod: paymentMethod,
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
  Future<List<CustomerOrder>> getOrders() async {
    try {
      return await _dataSource.fetchOrders();
    } on Object catch (_) {
      // Unlike a missing coupon hint, an empty list here is a *statement* —
      // "you have never ordered" — and the screen renders it as one. A failed
      // fetch must not be able to say that, so it surfaces as an error the user
      // can retry.
      throw const OrdersLoadFailure();
    }
  }

  @override
  Future<CustomerOrder?> getOrder(String orderId) async {
    try {
      return await _dataSource.fetchOrder(orderId);
    } on Object catch (_) {
      // Null already means "you have no such order", which the screen renders
      // as a dead end with a way back to the list. A failed fetch must not be
      // able to say that — it is a retry, not a verdict.
      throw const OrdersLoadFailure();
    }
  }

  @override
  Stream<OrderStatus> watchOrderStatus(String orderId) =>
      // Passed through untouched. A dropped subscription is not a failure the
      // customer needs a sentence about: the order still renders from what was
      // fetched, and the only thing lost is the live-ness.
      _dataSource.watchOrderStatus(orderId);

  @override
  Future<OrderRider?> getRider(String orderId) async {
    try {
      return await _dataSource.fetchRider(orderId);
    } on Object catch (_) {
      // Swallowed on purpose, and the one place in this class where that is the
      // right answer: the tracking card is already rendering the order. Failing
      // it over a name would be trading the screen for a nicety.
      return null;
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
