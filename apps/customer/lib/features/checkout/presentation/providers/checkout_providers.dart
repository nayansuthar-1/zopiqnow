import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/domain/entities/delivery_surcharge.dart';
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
  /// Pay-then-order is still the shape here, with two guards bolted to it since
  /// it cost real money: a preflight before the gateway (0120), and [_paidId]
  /// after it so a retry cannot charge twice. Inverting the shape properly —
  /// writing the order first as `pending_payment` — is the real answer and is
  /// deliberately not this.
  ///
  /// The amount charged is the *server's* total, from `checkout_preflight`, not
  /// the cart's. `place_order` reprices once more and its receipt is still the
  /// number that counts, but the two now start from the same arithmetic — a
  /// disagreement between them is a charge the payment gate then refuses.
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

  /// The gateway reference for a payment **already taken** for this attempt.
  ///
  /// [_attemptKey] made the retry safe at the wrong end. It is `place_order`
  /// that it makes idempotent — and `place_order` is not where the money is
  /// taken. So a placement that failed *after* the charge went through sent the
  /// customer back to a button that opened the gateway again: two captures, and
  /// at most one order to show for them.
  ///
  /// Held for exactly the same lifetime as [_attemptKey] and cleared in the same
  /// breath, because they are two halves of one attempt: the key names the order
  /// that may already exist, this names the payment that certainly does. While
  /// it is set, the retry skips the gateway entirely and goes straight back to
  /// `place_order` with the payment it already holds.
  ///
  /// **In memory only, and that is a known limit rather than an oversight.** The
  /// notifier is rebuilt when the cart's subtotal changes, and the process can be
  /// killed outright — either way this is lost and the payment behind it is
  /// orphaned. Nothing in the schema can currently record that: `refunds.order_id`
  /// is `not null` with a foreign key to `orders`, so a payment that never became
  /// an order has nowhere to be written down. That is P3 in `BUGFIX_QUEUE.md`.
  /// What this field fixes is the case the customer can actually cause by
  /// tapping the button again, which is every ordinary occurrence of it.
  ///
  /// **One narrow case it makes slightly worse, stated rather than hidden.** The
  /// notifier resets on the cart's *subtotal*, so a retry after an edit that
  /// changed the cart while leaving the subtotal identical would reuse a payment
  /// made for the old basket. Two baskets worth the same can still cost
  /// different totals, because the tax follows each dish's GST rate. Before this
  /// field the retry simply re-charged, so the amount always matched.
  ///
  /// It is not worth machinery: every menu item on the platform is at one GST
  /// rate today, so the two totals are arithmetically identical, and when that
  /// stops being true the payment gate refuses an intent worth less than the
  /// order — which leaves the money orphaned, which is P3, which is where a
  /// payment with no order belongs anyway. Widening [build]'s watch to the whole
  /// cart would fix it and would also throw away an applied coupon every time
  /// somebody reordered their basket, which is a worse trade.
  String? _paidId;

  Future<PlacedOrder?> placeOrder({
    required Address deliveryAddress,
    required String userPhone,
  }) async {
    final Cart cart = ref.read(cartProvider);
    // Minted on the first attempt and reused by every retry of it. See the
    // field: surviving a failure is the entire behaviour.
    _attemptKey ??= _newAttemptKey();

    state = CheckoutState(coupon: state.coupon, isPlacingOrder: true);
    try {
      // A payment already taken for this attempt. Both steps below are skipped
      // when there is one — the gateway because charging twice for one dinner is
      // the bug this guards, and the preflight with it, because its whole job is
      // to keep money from being taken for a doomed order and the money is
      // already gone. What remains is `place_order`, carrying the same
      // idempotency key and the same payment id as the attempt that failed.
      String? paymentId = _paidId;

      if (paymentId == null) {
        // Everything `place_order` could refuse on, asked before a rupee moves
        // (migration 0120). Until this existed the gateway ran first and nine
        // separate rules could refuse afterwards — a kitchen that shut, a dish
        // that sold out, a coupon that expired — leaving the customer charged
        // for an order that does not exist and no refund row to hang the money
        // on, because `orders_refund_on_termination` fires on an order and
        // there is none. It throws [OrderPlacementFailure] with the service's
        // own sentence, which is the same sentence the customer would have seen
        // a moment later and several hundred rupees worse off.
        //
        // Not a guarantee: the cart can still go stale in the seconds the
        // payment sheet is open, and `place_order` re-checks everything. It
        // removes the ordinary occurrences, not the race.
        final int chargeable = await ref
            .read(orderRepositoryProvider)
            .preflight(
              cart: cart,
              deliveryAddress: deliveryAddress,
              couponCode: state.coupon?.code,
            );

        final PaymentOutcome outcome = await ref
            .read(paymentGatewayProvider)
            .pay(
              // The server's total. The screen's own `CartBill` used to decide
              // this, and the two should agree — the point is what happens when
              // they do not: the payment gate refuses an intent worth less than
              // the order it is spent on, so charging the phone's figure and
              // letting Postgres price the order is itself a charge followed by
              // a refusal. `checkoutBillProvider` still draws the bill the
              // customer reads; it no longer decides what they are charged.
              amount: chargeable,
              description: cart.restaurantName ?? 'Zopiq order',
            );
        switch (outcome) {
          case PaymentSucceeded(paymentId: final String id):
            paymentId = id;
            // Written down *before* the order is attempted, which is the whole
            // point: everything that can go wrong from here on is a retry, and
            // a retry must find this rather than the gateway.
            _paidId = id;
          case PaymentFailed(message: final String message):
            throw PaymentFailure(message);
          case PaymentCancelled():
            state = CheckoutState(coupon: state.coupon);
            return null;
        }
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
      // Both spent, and cleared together because they are two halves of one
      // attempt. A later order from this same notifier — the cart is cleared
      // below, so there will not be one, but it costs two lines to be sure —
      // must never reuse a key that already names an order, or it would be
      // answered with that order instead of being placed; and must never reuse
      // a payment that has already bought a dinner, or the gate would refuse it
      // as consumed.
      _attemptKey = null;
      _paidId = null;
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

/// What the hour and the weather are adding to delivery for this cart's kitchen
/// (migration 0129).
///
/// Keyed off the cart's restaurant, like [offersProvider] beside it, because
/// rain is a fact about a *town* and the kitchen is what places the order in
/// one. Empty cart, failed read or no restaurant all collapse to
/// [DeliverySurcharge.none] — the bill then quotes the plain fee, which is the
/// safe direction to be wrong in: the charge comes from `checkout_preflight` at
/// the moment of payment, so an under-quote costs a corrected total and never a
/// charge the customer did not see coming.
final AutoDisposeFutureProvider<DeliverySurcharge> deliverySurchargeProvider =
    FutureProvider.autoDispose<DeliverySurcharge>((Ref ref) {
      final String? restaurantId = ref.watch(
        cartProvider.select((Cart c) => c.restaurantId),
      );
      if (restaurantId == null) return DeliverySurcharge.none;
      return ref.watch(orderRepositoryProvider).getDeliverySurcharge(restaurantId);
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
  return CartBill.of(
    cart,
    discount: coupon?.discount ?? 0,
    // `.value` and not `.requireValue`: while the read is in flight this is
    // null and the bill shows the plain fee for a moment, rather than the
    // screen showing a spinner over a total the customer was already reading.
    surcharge: ref.watch(deliverySurchargeProvider).value ?? DeliverySurcharge.none,
  );
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
