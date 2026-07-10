import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_mock_datasource.dart';
import 'package:zopiqnow/features/checkout/data/repositories/order_repository_impl.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Data source binding. Overridden in tests to drop the fake network latency.
final Provider<OrderMockDataSource> orderDataSourceProvider =
    Provider<OrderMockDataSource>((Ref ref) => OrderMockDataSource());

/// Repository binding — the seam the UI depends on (SAD 7.4).
final Provider<OrderRepository> orderRepositoryProvider =
    Provider<OrderRepository>(
      (Ref ref) => OrderRepositoryImpl(ref.watch(orderDataSourceProvider)),
    );

/// Everything the checkout screen holds beyond the cart itself.
@immutable
class CheckoutState {
  const CheckoutState({
    this.coupon,
    this.couponError,
    this.isApplyingCoupon = false,
    this.paymentMethod = PaymentMethod.cod,
    this.isPlacingOrder = false,
  });

  final AppliedCoupon? coupon;

  /// Human-readable reason the last apply failed; null once cleared.
  final String? couponError;

  final bool isApplyingCoupon;
  final PaymentMethod paymentMethod;
  final bool isPlacingOrder;
}

/// Owns coupon and payment-method state and performs order placement.
class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    // An applied coupon was validated against a specific subtotal. If the cart
    // changes value — user goes back, edits, returns — that validation is
    // stale, so the whole checkout state resets rather than honouring a
    // discount the order service never approved.
    ref.watch(cartProvider.select((Cart c) => c.subtotal));
    return const CheckoutState();
  }

  Future<void> applyCoupon(String code) async {
    if (code.trim().isEmpty || state.isApplyingCoupon) return;
    state = CheckoutState(
      paymentMethod: state.paymentMethod,
      isApplyingCoupon: true,
    );
    try {
      final AppliedCoupon coupon = await ref
          .read(orderRepositoryProvider)
          .applyCoupon(code: code, subtotal: ref.read(cartProvider).subtotal);
      state = CheckoutState(
        paymentMethod: state.paymentMethod,
        coupon: coupon,
      );
    } on CouponFailure catch (failure) {
      state = CheckoutState(
        paymentMethod: state.paymentMethod,
        couponError: failure.message,
      );
    }
  }

  void removeCoupon() =>
      state = CheckoutState(paymentMethod: state.paymentMethod);

  void selectPaymentMethod(PaymentMethod method) =>
      state = CheckoutState(coupon: state.coupon, paymentMethod: method);

  /// Places the order, records it for the confirmation screen, and clears the
  /// cart. Throws [OrderPlacementFailure]; the caller surfaces it.
  Future<PlacedOrder> placeOrder({required Address deliveryAddress}) async {
    final Cart cart = ref.read(cartProvider);
    state = CheckoutState(
      coupon: state.coupon,
      paymentMethod: state.paymentMethod,
      isPlacingOrder: true,
    );
    try {
      final PlacedOrder order = await ref
          .read(orderRepositoryProvider)
          .placeOrder(
            cart: cart,
            // Not read from checkoutBillProvider: that provider watches this
            // controller, and reading it back from here is a dependency cycle.
            bill: CartBill.of(cart, discount: state.coupon?.discount ?? 0),
            deliveryAddress: deliveryAddress,
            paymentMethod: state.paymentMethod,
          );
      ref.read(lastPlacedOrderProvider.notifier).record(order);
      // Clearing the cart also resets this notifier (build watches subtotal).
      ref.read(cartProvider.notifier).clear();
      return order;
    } on Object {
      state = CheckoutState(
        coupon: state.coupon,
        paymentMethod: state.paymentMethod,
      );
      rethrow;
    }
  }
}

final NotifierProvider<CheckoutController, CheckoutState>
checkoutControllerProvider = NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

/// The bill the checkout screen shows: the cart's bill with the applied
/// coupon's discount folded in.
final Provider<CartBill> checkoutBillProvider = Provider<CartBill>((Ref ref) {
  final Cart cart = ref.watch(cartProvider);
  final AppliedCoupon? coupon = ref.watch(
    checkoutControllerProvider.select((CheckoutState s) => s.coupon),
  );
  return CartBill.of(cart, discount: coupon?.discount ?? 0);
});

/// The most recently placed order — what the confirmation screen renders.
///
/// Deliberately survives navigation: the success route is a real route, and a
/// rebuild mid-transition must not lose the receipt.
class LastPlacedOrderNotifier extends Notifier<PlacedOrder?> {
  @override
  PlacedOrder? build() => null;

  void record(PlacedOrder order) => state = order;
}

final NotifierProvider<LastPlacedOrderNotifier, PlacedOrder?>
lastPlacedOrderProvider = NotifierProvider<LastPlacedOrderNotifier, PlacedOrder?>(
  LastPlacedOrderNotifier.new,
);
