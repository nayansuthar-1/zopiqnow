import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_mock_datasource.dart';
import 'package:zopiqnow/features/checkout/data/repositories/order_repository_impl.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

OrderRepositoryImpl _repo() =>
    OrderRepositoryImpl(OrderMockDataSource(latency: Duration.zero));

const Address _address = Address(
  id: 'home',
  label: 'Home',
  line1: 'Banjara Hills',
  city: 'Hyderabad',
  latitude: 17.4126,
  longitude: 78.4482,
);

Cart _cartOf(int price) => Cart(
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  lines: <CartLine>[
    CartLine(
      item: MenuItem(
        id: 'a',
        name: 'Dish',
        description: '',
        price: price,
        isVeg: true,
      ),
      quantity: 1,
    ),
  ],
);

void main() {
  group('applyCoupon', () {
    test('WELCOME50 takes a flat ₹50 off at its minimum subtotal', () async {
      final AppliedCoupon coupon = await _repo().applyCoupon(
        code: 'WELCOME50',
        subtotal: 199,
      );

      expect(coupon.code, 'WELCOME50');
      expect(coupon.discount, 50);
    });

    test('rejects a cart below the coupon minimum, saying how far off', () {
      expect(
        () => _repo().applyCoupon(code: 'WELCOME50', subtotal: 150),
        throwsA(
          isA<CouponFailure>().having(
            (CouponFailure f) => f.message,
            'message',
            contains('₹49'),
          ),
        ),
      );
    });

    test('rejects an unknown code', () {
      expect(
        () => _repo().applyCoupon(code: 'FREELUNCH', subtotal: 999),
        throwsA(isA<CouponFailure>()),
      );
    });

    test('normalises case and whitespace before matching', () async {
      final AppliedCoupon coupon = await _repo().applyCoupon(
        code: '  welcome50 ',
        subtotal: 300,
      );

      expect(coupon.code, 'WELCOME50');
    });

    test('ZOPIQ20 is 20% of the subtotal…', () async {
      final AppliedCoupon coupon = await _repo().applyCoupon(
        code: 'ZOPIQ20',
        subtotal: 300,
      );

      expect(coupon.discount, 60);
    });

    test('…capped at ₹100', () async {
      final AppliedCoupon coupon = await _repo().applyCoupon(
        code: 'ZOPIQ20',
        subtotal: 900,
      );

      expect(coupon.discount, 100);
    });
  });

  group('placeOrder', () {
    test('prices the order itself rather than trusting a submitted total', () async {
      final Cart cart = _cartOf(400);

      final PlacedOrder order = await _repo().placeOrder(
        cart: cart,
        deliveryAddress: _address,
        paymentMethod: PaymentMethod.cod,
        userId: 'usr_1',
        userPhone: '+919876543210',
      );

      expect(order.id, startsWith('ZPQ-'));
      expect(order.restaurantName, 'Test Kitchen');
      expect(order.deliveryTo, 'Banjara Hills, Hyderabad');
      // 400 subtotal + 40 delivery + 20 tax, computed by the order service.
      expect(order.total, CartBill.of(cart).total);
      expect(order.paymentMethod, PaymentMethod.cod);
      expect(order.etaMinutes, inInclusiveRange(25, 35));
    });

    test('applies the coupon it validates, not one the caller asserts', () async {
      final Cart cart = _cartOf(400);

      final PlacedOrder order = await _repo().placeOrder(
        cart: cart,
        deliveryAddress: _address,
        paymentMethod: PaymentMethod.cod,
        userId: 'usr_1',
        userPhone: '+919876543210',
        couponCode: 'WELCOME50',
      );

      expect(order.total, CartBill.of(cart, discount: 50).total);
    });

    test('rejects a coupon the cart does not qualify for, and says why', () async {
      // WELCOME50 needs a subtotal of 199; this cart is 100.
      expect(
        () => _repo().placeOrder(
          cart: _cartOf(100),
          deliveryAddress: _address,
          paymentMethod: PaymentMethod.cod,
          userId: 'usr_1',
          userPhone: '+919876543210',
          couponCode: 'WELCOME50',
        ),
        throwsA(
          isA<OrderPlacementFailure>().having(
            (OrderPlacementFailure f) => f.message,
            'message',
            contains('₹99 more'),
          ),
        ),
      );
    });

    test('issues a fresh order id every time', () async {
      final OrderRepositoryImpl repo = _repo();
      final Cart cart = _cartOf(400);

      final PlacedOrder first = await repo.placeOrder(
        cart: cart,
        deliveryAddress: _address,
        paymentMethod: PaymentMethod.cod,
        userId: 'usr_1',
        userPhone: '+919876543210',
      );
      final PlacedOrder second = await repo.placeOrder(
        cart: cart,
        deliveryAddress: _address,
        paymentMethod: PaymentMethod.cod,
        userId: 'usr_1',
        userPhone: '+919876543210',
      );

      expect(first.id, isNot(second.id));
    });
  });
}
