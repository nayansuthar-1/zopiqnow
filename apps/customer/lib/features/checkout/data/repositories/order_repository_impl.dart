import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_mock_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Default [OrderRepository] over the mock data source.
class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this._dataSource);

  final OrderMockDataSource _dataSource;

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
    required CartBill bill,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
  }) async {
    try {
      return await _dataSource.placeOrder(
        cart: cart,
        bill: bill,
        deliveryAddress: deliveryAddress,
        paymentMethod: paymentMethod,
      );
    } on Object catch (_) {
      throw const OrderPlacementFailure();
    }
  }
}
