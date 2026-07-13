import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_supabase_datasource.dart';
import 'package:zopiqnow/features/checkout/data/repositories/order_repository_impl.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/checkout/presentation/gateways/mock_payment_gateway.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// [OrderMockDataSource] to drop the network.
final Provider<OrderDataSource> orderDataSourceProvider =
    Provider<OrderDataSource>((Ref ref) => const OrderSupabaseDataSource());

/// Payment gateway binding — the seam Razorpay slots into once the keys and the
/// payment-order endpoint exist (Step 7). Until then, the mock settles UPI.
final Provider<PaymentGateway> paymentGatewayProvider = Provider<PaymentGateway>(
  (Ref ref) =>
      MockPaymentGateway(navigatorKey: ref.watch(rootNavigatorKeyProvider)),
);

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
  /// cart.
  ///
  /// Prepaid methods go through the gateway first. Returns null when the
  /// customer dismissed the payment sheet — nothing was charged and nothing was
  /// ordered, so there is nothing to say. Throws [PaymentFailure] on a decline
  /// and [OrderPlacementFailure] on a transport error; the caller surfaces both.
  ///
  /// Pay-then-order is still the shape here. Verifying the payment with Razorpay
  /// server-side inverts it (create payment order → settle → verify signature),
  /// but that reshuffle lives behind this method.
  ///
  /// The bill computed here is what the *gateway* is asked to charge. It is not
  /// what the order costs: `place_order` reprices the cart in Postgres, and the
  /// receipt it returns is the number that counts.
  /// [userPhone] is E.164 and non-null: an account can exist without a number
  /// (sign-in is by email), but an order cannot. Checkout collects it before it
  /// gets here — see `showDeliveryPhoneSheet`. Who is buying is not passed at
  /// all: `place_order` reads that from the session's JWT.
  Future<PlacedOrder?> placeOrder({
    required Address deliveryAddress,
    required String userPhone,
  }) async {
    final Cart cart = ref.read(cartProvider);
    // Not read from checkoutBillProvider: that provider watches this
    // controller, and reading it back from here is a dependency cycle.
    final CartBill bill = CartBill.of(
      cart,
      discount: state.coupon?.discount ?? 0,
    );
    state = CheckoutState(
      coupon: state.coupon,
      paymentMethod: state.paymentMethod,
      isPlacingOrder: true,
    );
    try {
      String? paymentId;
      if (state.paymentMethod == PaymentMethod.upi) {
        final PaymentOutcome outcome = await ref
            .read(paymentGatewayProvider)
            .pay(
              amount: bill.total,
              description: cart.restaurantName ?? 'Zopiq order',
            );
        switch (outcome) {
          case PaymentSucceeded(paymentId: final String id):
            paymentId = id;
          case PaymentFailed(message: final String message):
            throw PaymentFailure(message);
          case PaymentCancelled():
            state = CheckoutState(
              coupon: state.coupon,
              paymentMethod: state.paymentMethod,
            );
            return null;
        }
      }

      final PlacedOrder order = await ref
          .read(orderRepositoryProvider)
          .placeOrder(
            cart: cart,
            deliveryAddress: deliveryAddress,
            paymentMethod: state.paymentMethod,
            userPhone: userPhone,
            // The code, not the discount. What it is worth is the service's
            // call, made again against the subtotal the service computes.
            couponCode: state.coupon?.code,
            paymentId: paymentId,
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

/// Codes the checkout screen advertises. Empty on failure — a missing hint must
/// never take checkout down.
final FutureProvider<List<String>> couponHintsProvider =
    FutureProvider<List<String>>(
      (Ref ref) => ref.watch(orderRepositoryProvider).getCouponHints(),
    );

/// The bill the checkout screen shows: the cart's bill with the applied
/// coupon's discount folded in.
///
/// An estimate, and labelled as one in [CheckoutController.placeOrder]: the
/// order service reprices everything and its receipt is what the customer pays.
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
