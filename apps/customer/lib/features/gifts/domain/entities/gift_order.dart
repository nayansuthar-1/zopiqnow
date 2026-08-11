import 'package:flutter/foundation.dart';

/// Where a gift order has got to (migration 0096).
///
/// Shorter than the food ladder and every step means something the customer can
/// act on or wait for. There is no "packed": Zopiqnow packs it and couriers it,
/// and a state nobody can do anything about is a state somebody forgets to set.
enum GiftOrderStatus {
  /// Paid for, and we know about it.
  placed('placed', 'Order placed'),

  /// Somebody at Zopiqnow has it and is putting it together.
  accepted('accepted', 'Being prepared'),

  /// Handed to a courier. This is the state that carries [GiftOrder.courierName]
  /// and a tracking reference.
  dispatched('dispatched', 'On its way'),

  delivered('delivered', 'Delivered'),

  cancelled('cancelled', 'Cancelled');

  const GiftOrderStatus(this.wire, this.label);

  final String wire;
  final String label;

  /// An unknown wire value reads as [placed] — an older build should show the
  /// order under a vague heading, not crash on the way to it.
  static GiftOrderStatus fromWire(String wire) => values.firstWhere(
    (GiftOrderStatus s) => s.wire == wire,
    orElse: () => placed,
  );

  /// Still going somewhere.
  bool get isOpen =>
      this == placed || this == accepted || this == dispatched;

  // No `canCancel`. A gift order is final once it is placed (0116). `cancelled`
  // remains a status because Zopiqnow itself may still have to end an order it
  // cannot fulfil — that is an admin's act, not a button on this screen.

  /// How far along the four-step tracker, or null for a cancelled order which
  /// is not on the tracker at all.
  int? get step => switch (this) {
    placed => 0,
    accepted => 1,
    dispatched => 2,
    delivered => 3,
    cancelled => null,
  };
}

/// One line on a gift receipt.
@immutable
class GiftOrderLine {
  const GiftOrderLine({
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.taxAmount,
  });

  factory GiftOrderLine.fromJson(Map<String, dynamic> json) => GiftOrderLine(
    name: json['name'] as String,
    unitPrice: (json['unit_price'] as num).toInt(),
    quantity: (json['quantity'] as num).toInt(),
    lineTotal: (json['line_total'] as num).toInt(),
    taxAmount: (json['tax_amount'] as num).toInt(),
  );

  final String name;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final int taxAmount;
}

/// What a gift bag costs, priced by the service before a rupee is charged
/// (`gift_bag_quote`, migration 0112).
///
/// The bag knows its own subtotal and deliberately nothing else: the GST rate is
/// per item and the rounding is per slab, so a total worked out on the phone
/// would be an estimate of the receipt rather than the receipt. This is the
/// receipt, fetched before the gateway is opened, and [total] is the amount the
/// gateway is asked for.
@immutable
class GiftQuote {
  const GiftQuote({
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    required this.total,
  });

  factory GiftQuote.fromJson(Map<String, dynamic> json) => GiftQuote(
    subtotal: (json['subtotal'] as num).toInt(),
    deliveryFee: (json['delivery_fee'] as num).toInt(),
    taxes: (json['taxes'] as num).toInt(),
    total: (json['total'] as num).toInt(),
  );

  final int subtotal;
  final int deliveryFee;
  final int taxes;
  final int total;
}

/// A gift somebody bought.
@immutable
class GiftOrder {
  const GiftOrder({
    required this.id,
    required this.shopName,
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    required this.total,
    required this.status,
    required this.deliveryTo,
    required this.createdAt,
    required this.itemCount,
    this.statusReason,
    this.courierName,
    this.trackingRef,
    this.dispatchedAt,
    this.deliveredAt,
  });

  factory GiftOrder.fromJson(Map<String, dynamic> json) => GiftOrder(
    id: json['id'] as String,
    shopName: json['shop_name'] as String,
    subtotal: (json['subtotal'] as num).toInt(),
    deliveryFee: (json['delivery_fee'] as num?)?.toInt() ?? 0,
    taxes: (json['taxes'] as num).toInt(),
    total: (json['total'] as num).toInt(),
    status: GiftOrderStatus.fromWire(json['status'] as String),
    statusReason: json['status_reason'] as String?,
    courierName: json['courier_name'] as String?,
    trackingRef: json['tracking_ref'] as String?,
    deliveryTo: json['delivery_to'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    dispatchedAt: switch (json['dispatched_at']) {
      final String s => DateTime.parse(s).toLocal(),
      _ => null,
    },
    deliveredAt: switch (json['delivered_at']) {
      final String s => DateTime.parse(s).toLocal(),
      _ => null,
    },
    itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String shopName;
  final int subtotal;

  /// Zero today. The column exists so a courier charge is one UPDATE away
  /// rather than a migration (0096) — and so the receipt is already built to
  /// show it the day it stops being zero.
  final int deliveryFee;

  final int taxes;
  final int total;
  final GiftOrderStatus status;

  /// Why it was called off. Null for every order that was not.
  final String? statusReason;

  /// Who is carrying it, and the number to chase them with. Both null until it
  /// is dispatched; the tracking reference stays null for a courier that issues
  /// none, which is why the screen shows whichever of the two it has.
  final String? courierName;
  final String? trackingRef;

  final String deliveryTo;
  final DateTime createdAt;
  final DateTime? dispatchedAt;
  final DateTime? deliveredAt;
  final int itemCount;
}

/// A gift order the service refused, with its own sentence — "Something in your
/// gift bag is no longer available.", "That is a lot of orders at once." Those
/// are answers, not errors to bury.
class GiftOrderFailure implements Exception {
  const GiftOrderFailure([
    this.message = 'We couldn\'t place that order. Please try again.',
  ]);

  final String message;
}
