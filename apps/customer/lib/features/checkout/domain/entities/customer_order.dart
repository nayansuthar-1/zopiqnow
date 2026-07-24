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
    this.restaurantImageUrl = '',
    this.couponCode,
    this.paymentId,
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

  final OrderStatus status;

  /// Local time. The database stores `timestamptz`.
  final DateTime placedAt;

  final String deliveryTo;
  final int etaMinutes;

  final PaymentMethod paymentMethod;

  /// The gateway's reference for a prepaid order; null for cash.
  final String? paymentId;

  final int subtotal;
  final int deliveryFee;
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
