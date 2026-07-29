import 'dart:math' as math;

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// In-memory stand-in for the order service, faithful to the contract the real
/// endpoints will enforce: coupons carry a minimum order value and a discount
/// cap, and validation happens service-side against the submitted subtotal.
///
/// Modelling the rules now means the coupon field already has "unknown code"
/// and "cart too small" states to render, and the HTTP swap (Step 7) changes
/// the transport, not the UI's failure modes.
class OrderMockDataSource implements OrderDataSource {
  OrderMockDataSource({this.latency = const Duration(milliseconds: 600)});

  final Duration latency;

  /// The coupon book the real promotions service will own. The checkout screen
  /// surfaces these codes as hints — there is no campaign to learn them from.
  static const List<CouponRule> coupons = <CouponRule>[
    CouponRule(code: 'WELCOME50', minSubtotal: 199, flatOff: 50),
    CouponRule(code: 'ZOPIQ20', minSubtotal: 299, percentOff: 20, maxOff: 100),
  ];

  int _orderSeq = 0;

  /// Orders this instance has placed, newest last. The real history lives in
  /// Postgres and outlives the process; this one exists so the flow after
  /// checkout — place an order, open "Your orders", see it — can be exercised
  /// without a network.
  final List<CustomerOrder> _history = <CustomerOrder>[];

  /// The mock has no restaurant-scoped offers — every code in its book is a
  /// platform one, which is exactly what `restaurant_offers` returns for a
  /// kitchen that has created none. So the argument is accepted and ignored.
  @override
  Future<List<RestaurantOffer>> fetchOffers(String restaurantId) async =>
      coupons
          .map(
            (CouponRule r) => RestaurantOffer(
              code: r.code,
              label: r.label,
              minSubtotal: r.minSubtotal,
              isExclusive: false,
            ),
          )
          .toList(growable: false);

  /// Reviews the mock has taken, keyed by order. Enough to exercise the two
  /// states the screen actually has — "not rated" and "rated, still editable" —
  /// without pretending to enforce a window nothing here can advance the clock
  /// past.
  final Map<String, OrderReview> _reviews = <String, OrderReview>{};

  @override
  Future<OrderReviewState> fetchReviewState(String orderId) async {
    await Future<void>.delayed(latency);
    for (final CustomerOrder o in _history) {
      if (o.id == orderId) {
        return OrderReviewState(
          canReview: o.status == OrderStatus.delivered,
          hasRider: o.status == OrderStatus.delivered,
          riderName: 'Imran',
        );
      }
    }
    return OrderReviewState.none;
  }

  @override
  Future<OrderReview?> fetchMyReview(String orderId) async {
    await Future<void>.delayed(latency);
    return _reviews[orderId];
  }

  @override
  Future<void> submitReview({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  }) async {
    await Future<void>.delayed(latency);
    final DateTime now = DateTime.now();
    _reviews[orderId] = OrderReview(
      foodRating: foodRating,
      riderRating: riderRating,
      comment: comment,
      createdAt: _reviews[orderId]?.createdAt ?? now,
      editableUntil:
          _reviews[orderId]?.editableUntil ?? now.add(const Duration(hours: 1)),
    );
  }

  /// No invoice without an order service to issue the number. Refused with the
  /// service's own sentence rather than faked: an invoice with a made-up serial
  /// on it is worse than no invoice, and this is the one screen where a
  /// plausible stand-in would be actively misleading.
  @override
  Future<OrderInvoice> fetchInvoice(String orderId) async {
    await Future<void>.delayed(latency);
    throw const InvoiceFailure(
      'An invoice is issued once your order has been delivered.',
    );
  }

  @override
  Future<List<CustomerOrder>> fetchOrders() async {
    await Future<void>.delayed(latency);
    return _history.reversed.toList(growable: false);
  }

  @override
  Future<CustomerOrder?> fetchOrder(String orderId) async {
    await Future<void>.delayed(latency);
    for (final CustomerOrder o in _history) {
      if (o.id == orderId) return o;
    }
    return null;
  }

  /// The order's status, once.
  ///
  /// It does not advance, and that is the honest shape: what moves an order
  /// through the kitchen is the kitchen, and in its absence a cron job in
  /// Postgres (migration 0008). Neither is something an in-memory fake can
  /// stand in for — a fake that marched an order to 'delivered' on a timer
  /// would be testing its own timer. What this *does* model is the contract the
  /// screen is built against: a stream that opens with the current status.
  @override
  Stream<OrderStatus> watchOrderStatus(String orderId) {
    for (final CustomerOrder o in _history) {
      if (o.id == orderId) return Stream<OrderStatus>.value(o.status);
    }
    return const Stream<OrderStatus>.empty();
  }

  /// Nobody is ever carrying a mock order.
  ///
  /// A rider is not something this can fake honestly: one exists because a real
  /// person opened the rider app and claimed the job, and inventing one here
  /// would put a name and a phone number on the tracking card of an order that
  /// no one is delivering. Null is the truthful answer, and it is also the one
  /// the card is built to handle.
  @override
  Future<OrderRider?> fetchRider(String orderId) async => null;

  @override
  Future<String?> fetchDeliveryCode(String orderId) async => null;

  /// No map without a backend. The mock has never had coordinates for anything
  /// — no restaurant location, no delivery pin — and inventing a pair here would
  /// put a fake bike on a fake road, which is a demo of the wrong thing. The
  /// tracking card renders the rest of itself and simply has no map.
  @override
  Future<DeliveryRoute?> fetchRoute(String orderId) async => null;

  /// Likewise. Nothing is carrying a mock order, so nothing has a position.
  @override
  Stream<RiderPosition?> watchRiderPosition(String carrierKey) =>
      Stream<RiderPosition?>.value(null);

  /// No thread without the other end of it. Nobody is carrying a mock order, so
  /// there is nobody to talk to — the same answer [fetchRider] gives, and the
  /// chat button is hidden by the same absence of a rider.
  @override
  Future<List<CannedMessage>> fetchMessageMenu() async =>
      const <CannedMessage>[];

  @override
  Stream<List<OrderMessage>> watchMessages(String orderId) =>
      Stream<List<OrderMessage>>.value(const <OrderMessage>[]);

  /// Refuses in the same words `send_order_message` refuses in. A fake that
  /// accepted a message nobody would ever receive is a fake that teaches the
  /// sheet the wrong lesson.
  @override
  Future<void> sendMessage({
    required String orderId,
    required String code,
  }) async {
    throw const OrderMessageFailure(
      'There is nobody on this order to message right now.',
    );
  }

  @override
  Future<void> markMessagesRead(String orderId) async {}

  /// Calls a mock order off, refusing on exactly the statuses `cancel_my_order`
  /// refuses on — and with the same sentence. A fake that let a customer cancel
  /// an order the real service would not is a fake that teaches the screen the
  /// wrong lesson.
  @override
  Future<void> cancelOrder({required String orderId, String? reason}) async {
    await Future<void>.delayed(latency);

    final int index = _history.indexWhere(
      (CustomerOrder o) => o.id == orderId,
    );
    if (index < 0) {
      throw const OrderCancelFailure('We couldn\'t find that order.');
    }

    final CustomerOrder order = _history[index];
    if (order.status.cannotCancelBecause case final String refusal) {
      throw OrderCancelFailure(refusal);
    }

    _history[index] = CustomerOrder(
      id: order.id,
      restaurantId: order.restaurantId,
      restaurantName: order.restaurantName,
      restaurantImageUrl: order.restaurantImageUrl,
      status: OrderStatus.cancelled,
      statusReason: reason?.trim().isEmpty ?? true
          ? 'Cancelled by the customer'
          : reason!.trim(),
      placedAt: order.placedAt,
      deliveryTo: order.deliveryTo,
      deliveryNotes: order.deliveryNotes,
      etaMinutes: order.etaMinutes,
      paymentMethod: order.paymentMethod,
      paymentId: order.paymentId,
      subtotal: order.subtotal,
      deliveryFee: order.deliveryFee,
      taxes: order.taxes,
      discount: order.discount,
      total: order.total,
      couponCode: order.couponCode,
      lines: order.lines,
    );
  }

  @override
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
  }) async {
    await Future<void>.delayed(latency);

    final String normalized = code.trim().toUpperCase();
    CouponRule? rule;
    for (final CouponRule r in coupons) {
      if (r.code == normalized) rule = r;
    }
    if (rule == null) {
      throw const CouponFailure('This code isn\'t valid.');
    }
    if (subtotal < rule.minSubtotal) {
      throw CouponFailure(
        'Add items worth ₹${rule.minSubtotal - subtotal} more to use '
        '${rule.code}.',
      );
    }
    return AppliedCoupon(code: rule.code, discount: rule.discountOn(subtotal));
  }

  @override
  Future<PlacedOrder> placeOrder({
    required Cart cart,
    required Address deliveryAddress,
    required PaymentMethod paymentMethod,
    required String userPhone,
    String? couponCode,
    String? paymentId,
    String? deliveryNotes,
  }) async {
    await Future<void>.delayed(latency);

    // Prices the order itself, exactly as `place_order` does in Postgres: the
    // caller hands over a cart and a code, never a total. Re-validating the
    // coupon here is not belt-and-braces — it is this mock refusing to be more
    // gullible than the service it stands in for.
    final int subtotal = cart.subtotal;
    final int discount = couponCode == null || couponCode.trim().isEmpty
        ? 0
        : (await applyCoupon(code: couponCode, subtotal: subtotal)).discount;
    final CartBill bill = CartBill.of(cart, discount: discount);

    _orderSeq++;
    final String id = 'ZPQ-${1000 + _orderSeq}';
    // Deterministic per restaurant, 25–35 min. A real ETA comes from the
    // dispatch engine with tracking (Step 8).
    final int etaMinutes =
        25 + (cart.restaurantId ?? '').hashCode.toUnsigned(32) % 11;

    _history.add(
      CustomerOrder(
        id: id,
        restaurantId: cart.restaurantId ?? '',
        restaurantName: cart.restaurantName ?? '',
        status: OrderStatus.placed,
        placedAt: DateTime.now(),
        deliveryTo: deliveryAddress.shortDisplay,
        deliveryNotes: deliveryNotes,
        etaMinutes: etaMinutes,
        paymentMethod: paymentMethod,
        paymentId: paymentId,
        subtotal: bill.subtotal,
        deliveryFee: bill.deliveryFee,
        taxes: bill.taxes,
        discount: bill.discount,
        total: bill.total,
        couponCode: couponCode,
        lines: cart.lines
            .map(
              (CartLine l) => OrderLine(
                menuItemId: l.item.id,
                name: l.item.name,
                unitPrice: l.item.price,
                quantity: l.quantity,
                lineTotal: l.lineTotal,
              ),
            )
            .toList(growable: false),
      ),
    );

    return PlacedOrder(
      id: id,
      restaurantName: cart.restaurantName ?? '',
      deliveryTo: deliveryAddress.shortDisplay,
      total: bill.total,
      paymentMethod: paymentMethod,
      paymentId: paymentId,
      etaMinutes: etaMinutes,
    );
  }
}

/// One row of the mock coupon book: either a flat discount or a capped
/// percentage, gated by a minimum order value.
class CouponRule {
  const CouponRule({
    required this.code,
    required this.minSubtotal,
    this.flatOff,
    this.percentOff,
    this.maxOff,
  }) : assert(
         (flatOff != null) ^ (percentOff != null && maxOff != null),
         'A rule is flat XOR capped-percent',
       );

  final String code;
  final int minSubtotal;
  final int? flatOff;
  final int? percentOff;
  final int? maxOff;

  int discountOn(int subtotal) =>
      flatOff ?? math.min((subtotal * percentOff! / 100).round(), maxOff!);

  /// The rule in words, e.g. `₹50 off` — the half of [summary] that is not the
  /// code, and the same sentence `restaurant_offers` builds server-side.
  String get label =>
      flatOff != null ? '₹$flatOff off' : '$percentOff% off up to ₹$maxOff';

  /// What the checkout screen's hint shows, e.g. `WELCOME50 · ₹50 off`.
  String get summary => '$code · $label';
}
