import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';

/// Where an order is in its life. The wire values are the ones the `orders.status`
/// check constraint allows.
enum OrderStatus {
  placed('Placed'),
  accepted('Accepted'),
  preparing('Preparing'),
  readyForPickup('Ready'),
  outForDelivery('Out for delivery'),
  delivered('Delivered'),
  // The restaurant declined a new order before accepting it — different from a
  // cancellation, which happens after. Both end the order; the words differ.
  rejected('Not accepted'),
  cancelled('Cancelled');

  const OrderStatus(this.label);

  /// What the customer reads on the status chip.
  final String label;

  /// Throws [ArgumentError] on anything else. The database enumerates exactly
  /// these values, so an unknown one is not a status we forgot to handle — it is
  /// the client and the schema having drifted apart, and a receipt rendered
  /// from a contract we no longer understand is worse than one that fails.
  static OrderStatus fromWire(String value) => switch (value) {
    'placed' => placed,
    'accepted' => accepted,
    'preparing' => preparing,
    'ready_for_pickup' => readyForPickup,
    'out_for_delivery' => outForDelivery,
    'delivered' => delivered,
    'rejected' => rejected,
    'cancelled' => cancelled,
    _ => throw ArgumentError.value(value, 'status', 'Unknown order status'),
  };

  /// Still on its way — the order has not ended, one way or another. An open
  /// order is one worth watching: it is what decides whether the detail screen
  /// subscribes to live status or renders a receipt.
  bool get isOpen => this != delivered && this != cancelled && this != rejected;

  /// Whether the customer may still call this order off.
  ///
  /// Mirrors `cancel_my_order` in migration 0051, and mirroring it is the point:
  /// the button is offered exactly when the database will honour it. The line is
  /// drawn where cooking starts — before that, calling off an order costs
  /// nobody anything; after it, food has been made and it is a refund
  /// conversation instead. If the two ever disagree the database wins, and
  /// [cannotCancelBecause] is what the screen shows.
  bool get isCancellable => this == placed || this == accepted;

  /// Why the order can no longer be called off, in the words the customer
  /// reads, or null while it still can be.
  ///
  /// A sentence and not a disabled button: "you cannot do this" with no reason
  /// attached is the thing that makes someone phone the restaurant. These match
  /// `cancel_my_order`'s refusals — the same news, whether it arrives before the
  /// tap or after it.
  String? get cannotCancelBecause => switch (this) {
    placed || accepted => null,
    preparing => 'The kitchen has already started cooking this order.',
    readyForPickup => 'Your order is packed and waiting for a rider.',
    outForDelivery => 'Your order is already on its way.',
    delivered => 'This order has already been delivered.',
    rejected || cancelled => 'This order has already ended.',
  };

  /// The stages an order that goes well passes through, in order.
  ///
  /// Neither [cancelled] nor [rejected] is among them, and that is not an
  /// omission: an order that ended has left the journey, and the tracking screen
  /// says so instead of drawing a timeline it will never finish.
  static const List<OrderStatus> journey = <OrderStatus>[
    placed,
    accepted,
    preparing,
    readyForPickup,
    outForDelivery,
    delivered,
  ];

  /// How far along [journey] this status is; `-1` for an order that ended.
  int get step => journey.indexOf(this);
}

/// The two things about an open order that change while somebody is watching it:
/// where it is in its life, and when it is now expected.
///
/// **Why they travel together.** Both live in the same `orders` row and both
/// arrive on the same subscription, so carrying them as one value is one socket
/// rather than two. It also fixes a real gap: the arrival time is recomputed on
/// the server every time the rider moves (0057, and along the road since 0102),
/// and until this existed the only thing that could make the screen re-read it
/// was a *status* change — so a customer could watch a stationary "arriving by
/// 8:40" for the whole of a delivery that the server knew was running late.
///
/// **Value equality is the load-bearing part.** Riverpod does not notify
/// listeners when a provider re-emits an equal value, so a row written for some
/// other reason costs nothing, and the screen redraws exactly when one of these
/// two actually moved.
@immutable
class OrderProgress {
  const OrderProgress({required this.status, this.etaAt, this.etaReason});

  final OrderStatus status;

  /// When the order is now expected, or null on an order that has no estimate
  /// to give — a delivered one, or one placed before there was anywhere to put
  /// the number.
  final DateTime? etaAt;

  /// Why the estimate moved *later*, in the words the customer reads, or null.
  /// Never set when the news is good: 0057 writes a reason only in the direction
  /// that costs the customer something.
  final String? etaReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderProgress &&
          other.status == status &&
          other.etaAt == etaAt &&
          other.etaReason == etaReason;

  @override
  int get hashCode => Object.hash(status, etaAt, etaReason);
}

/// One line of a past order, priced **as it was charged**.
///
/// Not a [MenuItem]: the dish may since have been renamed, repriced, or delisted,
/// and a receipt that changes after the fact is not a receipt. Reorder resolves
/// [menuItemId] against today's menu, which is exactly where that difference is
/// supposed to surface.
@immutable
class OrderLine {
  const OrderLine({
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.options = const <String>[],
  });

  final String menuItemId;
  final String name;
  final int unitPrice;
  final int quantity;
  final int lineTotal;

  /// The variant/add-ons chosen for this line, by name — "Full", "Extra cheese"
  /// (migration 0048). Empty for a plain line.
  final List<String> options;

  /// The chosen options as one line, or empty.
  String get optionsLabel => options.join(', ');
}

/// An order the customer has already placed, as order history renders it.
///
/// Distinct from `PlacedOrder`, which is the *receipt* the order service hands
/// back at checkout — a confirmation screen needs a total and an ETA, and this
/// needs a whole bill. Merging them would give each screen the other's fields to
/// ignore.
@immutable
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.status,
    required this.placedAt,
    required this.deliveryTo,
    required this.etaMinutes,
    required this.paymentMethod,
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    required this.discount,
    required this.total,
    required this.lines,
    this.platformFee = 0,
    this.packagingFee = 0,
    this.surgeFee = 0,
    this.restaurantImageUrl = '',
    this.restaurantPhone,
    this.deliveryNotes,
    this.couponCode,
    this.paymentId,
    this.statusReason,
  });

  /// Human-readable reference, e.g. `ZPQ-1042`.
  final String id;

  final String restaurantId;

  /// Stored on the order, not read from the catalog: a delisted restaurant must
  /// not blank the name on an order the customer already paid for.
  final String restaurantName;

  /// Decoration, and the one field here that *is* read from the live catalog —
  /// so it is empty for a delisted restaurant, and the UI falls back.
  final String restaurantImageUrl;

  /// The kitchen's number, read from the live catalog like the photo above it
  /// (0027 added the column; B5 is what finally shows it). Null on every seeded
  /// restaurant and on any an admin has not filled in — and a null here means no
  /// Call button, not an empty one.
  final String? restaurantPhone;

  final OrderStatus status;

  /// Why the order ended, when it ended early — the kitchen's note on a
  /// rejection or a cancellation, the customer's own words when they called it
  /// off, or the sweeper's sentence when nobody accepted it in time (0051).
  /// Null for every order that is still running or that ran to completion.
  final String? statusReason;

  /// Local time. The database stores `timestamptz`.
  final DateTime placedAt;

  final String deliveryTo;

  /// What the customer told the rider about their own front door — "gate 2, the
  /// blue door" (0061). Frozen onto the order at checkout rather than read back
  /// off the address, so editing the address later cannot rewrite what the rider
  /// was actually told. Null when nothing was said.
  final String? deliveryNotes;

  final int etaMinutes;

  final PaymentMethod paymentMethod;

  /// The gateway's reference for a prepaid order; null for cash.
  final String? paymentId;

  final int subtotal;

  /// The fee stack (migration 0078), each line gross — the GST inside them is
  /// already there and is never added on top. Everything but the delivery fee
  /// is 0 on every order placed so far; the rows exist so that the day one is
  /// switched on, the bill on this screen still adds up to [total] instead of
  /// silently losing a line.
  final int deliveryFee;
  final int platformFee;
  final int packagingFee;
  final int surgeFee;

  /// GST on the food. Since 0078 it is charged on the discounted value; before
  /// it, on the full subtotal.
  final int taxes;
  final int discount;
  final int total;

  final String? couponCode;

  final List<OrderLine> lines;

  int get itemCount => lines.fold(0, (int sum, OrderLine l) => sum + l.quantity);

  /// One-line summary for the history card, e.g. `2 × Biryani, 1 × Coke`.
  String get itemsLabel =>
      lines.map((OrderLine l) => '${l.quantity} × ${l.name}').join(', ');
}
