import 'package:flutter/foundation.dart';

/// Where an order is in its life.
///
/// Deliberately a *copy* of the customer app's enum rather than a shared one.
/// The contract both apps answer to is the `orders.status` check constraint in
/// Postgres — that is the single source of truth, and it is the schema, not a
/// Dart file. Extracting a shared domain package to hold six strings would mean
/// a third package, a refactor of every import in the customer app, and a new
/// place for the two to disagree with the database. If they drift, the database
/// rejects the write; that is the guard that matters.
enum OrderStatus {
  placed('New'),
  accepted('Accepted'),
  preparing('Preparing'),
  outForDelivery('Out for delivery'),
  delivered('Delivered'),
  cancelled('Cancelled');

  const OrderStatus(this.label);

  /// What the kitchen reads. Note `placed` is **"New"** here and "Placed" in the
  /// customer app: the same row, and the two audiences do not mean the same
  /// thing by it. To a customer it is a thing they have done; to a kitchen it is
  /// a thing that has *arrived*, and it is the only word on this screen that
  /// needs to make someone look up.
  final String label;

  static OrderStatus fromWire(String value) => switch (value) {
    'placed' => placed,
    'accepted' => accepted,
    'preparing' => preparing,
    'out_for_delivery' => outForDelivery,
    'delivered' => delivered,
    'cancelled' => cancelled,
    _ => throw ArgumentError.value(value, 'status', 'Unknown order status'),
  };

  /// The value the database understands. `outForDelivery` is `out_for_delivery`
  /// on the wire, and `name` would send the camelCase — which the check
  /// constraint would refuse, correctly and unhelpfully.
  String get wire => switch (this) {
    placed => 'placed',
    accepted => 'accepted',
    preparing => 'preparing',
    outForDelivery => 'out_for_delivery',
    delivered => 'delivered',
    cancelled => 'cancelled',
  };

  /// Still the kitchen's problem — it is neither delivered nor cancelled. The
  /// queue is exactly the set of open orders.
  bool get isOpen => this != delivered && this != cancelled;

  /// The one status the kitchen can move this order to by pressing the big
  /// button, or null when there is nothing left to press.
  ///
  /// This mirrors `set_order_status` in migration 0009, and mirroring it is the
  /// point: the button offers what the database will accept. If they ever
  /// disagree the database wins — it raises, and the ticket says so — but a
  /// button that is *usually* refused is a button nobody trusts.
  OrderStatus? get next => switch (this) {
    placed => accepted,
    accepted => preparing,
    preparing => outForDelivery,
    outForDelivery => delivered,
    delivered || cancelled => null,
  };

  /// What the button *says*. "Accept" and "Start preparing" are imperatives; the
  /// status they produce is not the word a cook would use.
  String? get nextAction => switch (this) {
    placed => 'Accept order',
    accepted => 'Start preparing',
    preparing => 'Hand to rider',
    outForDelivery => 'Mark delivered',
    delivered || cancelled => null,
  };

  /// Cancellable up to the moment the food leaves. Once it is with the rider it
  /// is a refund conversation, not a status change — `set_order_status` refuses
  /// it, and this is why the button is not offered.
  bool get canCancel => this == placed || this == accepted || this == preparing;
}

/// How the customer is paying — which the kitchen cares about for one reason.
enum PaymentMethod {
  cod,
  upi;

  static PaymentMethod fromWire(String value) => value == 'upi' ? upi : cod;

  /// Cash orders mean the rider has to collect. Nothing else on this screen
  /// changes with the payment method.
  bool get isCash => this == cod;
}

/// One line of an order, as it was charged.
@immutable
class OrderLine {
  const OrderLine({
    required this.name,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final int lineTotal;
}

/// An order, as the kitchen needs to see it.
///
/// Not the customer's `CustomerOrder`, and not a subset of it either — it is a
/// different reading of the same row. The customer's version leads with what
/// they paid; this one leads with what to cook and who to call. `subtotal`,
/// `taxes` and `coupon_code` are not here at all: the kitchen is not owed the
/// customer's bill breakdown, and a screen that shows a number nobody acts on is
/// a screen with a number people misread.
@immutable
class VendorOrder {
  const VendorOrder({
    required this.id,
    required this.status,
    required this.placedAt,
    required this.customerPhone,
    required this.deliveryTo,
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    required this.discount,
    required this.total,
    required this.paymentMethod,
  });

  final String id;
  final OrderStatus status;

  /// Local time. The database stores `timestamptz`.
  final DateTime placedAt;

  /// The number the rider — or the kitchen, when something is out of stock —
  /// actually calls.
  final String customerPhone;

  final String deliveryTo;

  /// The bill, exactly as `place_order` priced it — never recomputed here. Not
  /// shown on the live queue ticket (a cook does not reconcile the customer's
  /// bill mid-rush), but the order-detail sheet lays it out, and History sums
  /// `total` into the day's revenue. Whole rupees.
  final int subtotal;
  final int deliveryFee;
  final int taxes;
  final int discount;

  /// What the order came to. On a cash order this is what the rider collects,
  /// which is the only reason it is on the live ticket. Equals
  /// `subtotal + deliveryFee + taxes - discount` — the database enforces it.
  final int total;

  final PaymentMethod paymentMethod;

  /// How long this ticket has been sitting there. The number a kitchen is
  /// actually judged on, and the reason the queue sorts oldest-first.
  Duration get age => DateTime.now().difference(placedAt);
}
