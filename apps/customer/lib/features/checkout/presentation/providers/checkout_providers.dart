import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_supabase_datasource.dart';
import 'package:zopiqnow/features/checkout/data/gateways/razorpay_payment_gateway.dart';
import 'package:zopiqnow/features/checkout/data/repositories/order_repository_impl.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/checkout/presentation/gateways/mock_payment_gateway.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';

/// Data source binding — Postgres, as of Step 7. Tests override it with
/// [OrderMockDataSource] to drop the network.
final Provider<OrderDataSource> orderDataSourceProvider =
    Provider<OrderDataSource>((Ref ref) => const OrderSupabaseDataSource());

/// Payment gateway binding (launch C2).
///
/// Razorpay is always bound. Whether it *acts* is the server's decision, not a
/// build-time one: `razorpay-order` answers `configured: false` while there are
/// no keys, and the adapter falls through to whatever is behind it. So the day
/// the keys are set as function secrets, every already-installed build starts
/// taking real payments — no release, no store review, no waiting.
///
/// **Behind it is the mock, in every build.** Debug, release, and a bundle
/// installed from Play all behave the same, which is the point: an order can be
/// placed on whatever build is in somebody's hand, without a `--dart-define`
/// that has to be remembered at build time and whose absence looks to the
/// customer like *"Payments aren't available in this build yet."*
///
/// **This is not the lock coming off, it is the lock moving to where it works.**
/// There were two, and the build-time one was the weaker:
///
/// 1. **The fallback is unreachable once Razorpay is configured.**
///    `RazorpayPaymentGateway` drops to it *only* when the server answers
///    `configured: false`, and it answers that only while there are no keys. The
///    day `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` are set as function secrets,
///    every already-installed build starts taking real payments and the mock
///    below stops being reached at all — with no release and no store review.
/// 2. **The database refuses an unpaid order outright.** `payment_settings.
///    require_verified_payment` drives the `orders_require_verified_payment`
///    trigger (0085) — server-side, authoritative, and applying to every client
///    that ever existed rather than to the ones compiled with the right flag.
///    It ships disarmed; **arming it is ship S5 and belongs to the day Razorpay
///    goes live.**
///
/// So the honest reading of the old arrangement is that a build flag was
/// standing in for a server setting. A flag can be forgotten in both directions:
/// forget it on a test build and nobody can order, forget to *remove* it on a
/// production one and the lock was never there anyway. The trigger cannot be
/// forgotten on a per-build basis, because there are no builds involved.
final Provider<PaymentGateway> paymentGatewayProvider = Provider<PaymentGateway>(
  (Ref ref) => RazorpayPaymentGateway(
    supabase: Supabase.instance.client,
    fallback: MockPaymentGateway(
      navigatorKey: ref.watch(rootNavigatorKeyProvider),
    ),
  ),
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
    this.isPlacingOrder = false,
  });

  final AppliedCoupon? coupon;

  /// Human-readable reason the last apply failed; null once cleared.
  final String? couponError;

  final bool isApplyingCoupon;
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

    // The cart names the kitchen, and the kitchen is half of what makes a code
    // valid (migration 0064). An empty cart has no restaurant and cannot have a
    // discount — there is nothing to take a percentage of.
    final Cart cart = ref.read(cartProvider);
    final String? restaurantId = cart.restaurantId;
    if (restaurantId == null) return;

    state = const CheckoutState(isApplyingCoupon: true);
    try {
      final AppliedCoupon coupon = await ref
          .read(orderRepositoryProvider)
          .applyCoupon(
            code: code,
            subtotal: cart.subtotal,
            restaurantId: restaurantId,
          );
      state = CheckoutState(coupon: coupon);
    } on CouponFailure catch (failure) {
      state = CheckoutState(couponError: failure.message);
    }
  }

  void removeCoupon() => state = const CheckoutState();

  /// Places the order, records it for the confirmation screen, and clears the
  /// cart.
  ///
  /// Every order is prepaid and goes through the gateway first — UPI is the only
  /// method checkout offers (launch C1). Returns null when the customer
  /// dismissed the payment sheet — nothing was charged and nothing was ordered,
  /// so there is nothing to say. Throws [PaymentFailure] on a decline and
  /// [OrderPlacementFailure] on a transport error; the caller surfaces both.
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
  /// The key that makes a retry safe (launch C4, migration 0086).
  ///
  /// Generated once per checkout attempt and **deliberately kept when placing
  /// fails**: the whole point is that the retry carries the same key, so a
  /// response lost on a bad connection is answered with the order that was
  /// already placed rather than a second one. Cleared on success.
  ///
  /// Not part of [CheckoutState], because that is rebuilt whenever the cart's
  /// subtotal changes — which is exactly right for a coupon and exactly wrong
  /// here: editing the cart makes this a different order, and a different order
  /// should get a different key. The notifier is recreated in that case anyway,
  /// which gives us the new key for free.
  String? _attemptKey;

  /// 128 bits from the platform's secure generator, hex-encoded. Not a UUID
  /// package: this needs to be unique for one customer over a few minutes, and
  /// that is not worth a dependency the version freeze would have to approve.
  static String _newAttemptKey() {
    final Random random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

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
    // Minted on the first attempt and reused by every retry of it. See the
    // field: surviving a failure is the entire behaviour.
    _attemptKey ??= _newAttemptKey();

    state = CheckoutState(coupon: state.coupon, isPlacingOrder: true);
    try {
      final String paymentId;
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
          state = CheckoutState(coupon: state.coupon);
          return null;
      }

      final PlacedOrder order = await ref
          .read(orderRepositoryProvider)
          .placeOrder(
            cart: cart,
            deliveryAddress: deliveryAddress,
            paymentMethod: PaymentMethod.upi,
            userPhone: userPhone,
            // The code, not the discount. What it is worth is the service's
            // call, made again against the subtotal the service computes.
            couponCode: state.coupon?.code,
            paymentId: paymentId,
            // Read here rather than passed in: the note is checkout's own state,
            // and the button that calls this already has enough arguments.
            deliveryNotes: ref.read(deliveryNotesProvider),
            idempotencyKey: _attemptKey,
          );
      // Spent. A later order from this same notifier — the cart is cleared
      // below, so there will not be one, but it costs a line to be sure — must
      // never reuse a key that already names an order, or it would be answered
      // with that order instead of being placed.
      _attemptKey = null;
      ref.read(lastPlacedOrderProvider.notifier).record(order);
      // Clearing the cart also resets this notifier (build watches subtotal).
      ref.read(cartProvider.notifier).clear();
      return order;
    } on Object {
      state = CheckoutState(coupon: state.coupon);
      rethrow;
    }
  }
}

final NotifierProvider<CheckoutController, CheckoutState>
checkoutControllerProvider = NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

/// What the rider will be told about this door, for *this* order.
///
/// Deliberately not a field of [CheckoutState]: that notifier rebuilds whenever
/// the cart's subtotal changes, because an applied coupon was validated against
/// a subtotal and goes stale with it. A note is not priced and does not go
/// stale — losing "gate 2, blue building" because somebody added a drink would
/// be a small daily insult.
///
/// It starts as whatever is saved on the selected address, so the common case is
/// typed once and never again, and switching address picks up that address's own
/// note. Overriding it here changes tonight's order and not the address book:
/// "the lift is out today" is not a fact about where you live.
class DeliveryNotesController extends Notifier<String?> {
  @override
  String? build() =>
      ref.watch(selectedAddressProvider)?.deliveryNotes;

  void set(String? notes) {
    final String trimmed = (notes ?? '').trim();
    state = trimmed.isEmpty ? null : trimmed;
  }
}

final NotifierProvider<DeliveryNotesController, String?> deliveryNotesProvider =
    NotifierProvider<DeliveryNotesController, String?>(
      DeliveryNotesController.new,
    );

/// The offers the checkout screen advertises: Zopiqnow's own, plus any this
/// kitchen is running (migration 0064).
///
/// Keyed off the cart's restaurant rather than fetched once for the session,
/// because "which offers apply" is now a question about *which restaurant* —
/// and a code from the last cart shown against this one would be a code the
/// order service refuses at the only moment that matters.
///
/// Empty on failure and on an empty cart: a missing hint must never take
/// checkout down.
final AutoDisposeFutureProvider<List<RestaurantOffer>> offersProvider =
    FutureProvider.autoDispose<List<RestaurantOffer>>((Ref ref) {
      final String? restaurantId = ref.watch(
        cartProvider.select((Cart c) => c.restaurantId),
      );
      if (restaurantId == null) return const <RestaurantOffer>[];
      return ref.watch(orderRepositoryProvider).getOffers(restaurantId);
    });

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
