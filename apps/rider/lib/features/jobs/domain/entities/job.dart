import 'package:flutter/foundation.dart';

/// Where the rider is on a job. Mirrors `deliveries.state` (migration 0025).
///
/// Deliberately a different axis from the order's own status: the customer app
/// throws on an order status it does not recognise, so the rider's lifecycle was
/// kept out of `orders.status` entirely.
/// The order is the order (0049): claimed → arrivedAtRestaurant → pickedUp →
/// arrivedAtCustomer → delivered. Each arrival is a step Postgres requires, not
/// one this app is trusted to lead the rider through — `confirm_pickup` refuses
/// from [claimed] and `confirm_delivered` refuses from [pickedUp].
enum JobState {
  claimed,
  arrivedAtRestaurant,
  pickedUp,
  arrivedAtCustomer,
  delivered,
  cancelled;

  static JobState fromWire(String value) => switch (value) {
    'claimed' => claimed,
    'arrived_at_restaurant' => arrivedAtRestaurant,
    'picked_up' => pickedUp,
    'arrived_at_customer' => arrivedAtCustomer,
    'delivered' => delivered,
    'cancelled' => cancelled,
    // Tolerant on purpose. A rider standing in a stairwell holding somebody's
    // dinner is the worst possible audience for a crash, and this drives one
    // line of copy and which button is showing — not a receipt.
    _ => claimed,
  };

  bool get isLive =>
      this == claimed ||
      this == arrivedAtRestaurant ||
      this == pickedUp ||
      this == arrivedAtCustomer;

  /// Collecting, as opposed to carrying. Which end of the ride the rider is at
  /// decides the map pin, the phone number and the next button.
  bool get isCollecting => this == claimed || this == arrivedAtRestaurant;
}

/// The single next move on a live job.
///
/// Derived from [JobState] rather than stored, so the card can never offer a
/// button the database would refuse — and there is only ever one, because a
/// screen read at a traffic light gets one decision.
enum JobStep { rideToRestaurant, collect, rideToCustomer, handOver, done }

/// A job on the board: an order that is cooked, or nearly, and unclaimed.
///
/// Note what is *not* here: the customer's phone number. The board is visible to
/// every signed-in rider, and a board that hands out phone numbers is a list of
/// everyone who ordered dinner tonight. It arrives with [Job] instead, after the
/// rider has committed — that is `available_deliveries` vs `my_deliveries` in
/// 0025, and the split is enforced in Postgres, not here.
///
/// Since B3 the board is the **leftovers**, not the front door: an order is
/// offered to riders one at a time and only reaches this list once the fleet has
/// declined or ignored it. What is here is genuinely available to anybody.
@immutable
class JobOffer {
  const JobOffer({
    required this.orderId,
    required this.restaurantName,
    required this.deliverTo,
    required this.total,
    required this.isCash,
    required this.isReady,
    required this.routeKm,
    required this.riderPay,
    required this.placedAt,
    required this.offeredToOther,
  });

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
    orderId: json['order_id'] as String,
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    deliverTo: json['deliver_to'] as String? ?? '',
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    isReady: json['status'] == 'ready_for_pickup',
    // `num`, not `int`: Postgres `numeric` arrives as either depending on
    // whether the value happens to be whole. Same reason as [Job.distanceKm].
    routeKm: (json['route_km'] as num?)?.toDouble(),
    riderPay: json['rider_pay'] as int? ?? 0,
    placedAt: DateTime.parse(json['placed_at'] as String).toLocal(),
    offeredToOther: json['offered_to_other'] as bool? ?? false,
  );

  final String orderId;
  final String restaurantName;
  final String deliverTo;
  final int total;

  /// How far the ride is, kitchen to door — the road distance when Ola has
  /// answered for this order, the straight line until then (0046). Null only
  /// when neither could be measured, which means the kitchen has no coordinates.
  final double? routeKm;

  /// What the job pays, at today's rate and [routeKm]. B3's rule: a rider must
  /// be able to see the distance and the fee **before** deciding, not after.
  final int riderPay;

  /// Whether the rider will be collecting cash. The one thing on the board worth
  /// knowing before accepting, because it changes what they carry.
  final bool isCash;

  /// Packed and waiting, as opposed to still being cooked. A rider can claim
  /// either — seeing a job while it cooks is what lets them ride over in time.
  final bool isReady;

  final DateTime placedAt;

  /// Somebody else's fifteen seconds are running on this job right now (0148).
  ///
  /// It stays on this rider's board because they were offered it too and their
  /// own window ran out — before 0148 it simply vanished from their screen the
  /// moment the dispatcher moved on, which is why a rider 300 m from the kitchen
  /// could lose a job to one 3 km away by being eight seconds late to their
  /// phone. They can still take it, and if both of them do, the nearer one gets
  /// it. The card says so before the tap rather than after.
  final bool offeredToOther;
}

/// A job the platform has picked this rider for, with a clock on it (0056).
///
/// The difference between this and [JobOffer] is the difference between being
/// *asked* and being *shown a list*. An offer is addressed to one rider, holds
/// the order off everybody else's board while it stands, and expires — decline
/// it, or say nothing, and it moves to the next partner within seconds.
///
/// [expiresAt] is an absolute instant rather than "seconds remaining", the same
/// trick 0052 used for the live card's ETA: the device counts down against its
/// own clock, so a countdown drawn on a phone that was asleep for thirty seconds
/// is correct the moment it appears rather than starting again from full.
@immutable
class DeliveryOffer {
  const DeliveryOffer({
    required this.orderId,
    required this.restaurantName,
    required this.restaurantLat,
    required this.restaurantLng,
    required this.deliverTo,
    required this.total,
    required this.isCash,
    required this.isReady,
    required this.routeKm,
    required this.toPickupKm,
    required this.riderPay,
    required this.offeredAt,
    required this.expiresAt,
  });

  factory DeliveryOffer.fromJson(Map<String, dynamic> json) => DeliveryOffer(
    orderId: json['order_id'] as String,
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    restaurantLat: (json['restaurant_lat'] as num?)?.toDouble(),
    restaurantLng: (json['restaurant_lng'] as num?)?.toDouble(),
    deliverTo: json['deliver_to'] as String? ?? '',
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    isReady: json['order_status'] == 'ready_for_pickup',
    routeKm: (json['route_km'] as num?)?.toDouble(),
    toPickupKm: (json['to_pickup_km'] as num?)?.toDouble(),
    riderPay: json['rider_pay'] as int? ?? 0,
    offeredAt: DateTime.parse(json['offered_at'] as String).toLocal(),
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
  );

  final String orderId;
  final String restaurantName;
  final double? restaurantLat;
  final double? restaurantLng;
  final String deliverTo;
  final int total;
  final bool isCash;
  final bool isReady;

  /// The ride itself, kitchen to door.
  final double? routeKm;

  /// How far the rider is from the kitchen right now — the reason *they* were
  /// picked, frozen at the moment of the offer (0056). Null when the platform
  /// had no position for them, which is honest: the sheet then says nothing
  /// about distance rather than showing a confident zero.
  final double? toPickupKm;

  final int riderPay;
  final DateTime offeredAt;
  final DateTime expiresAt;

  /// How long the whole countdown was, so a progress ring can draw a fraction
  /// without hard-coding the forty-five seconds the database chose.
  Duration get window => expiresAt.difference(offeredAt);

  /// What is left, floored at zero — a negative duration on a sheet that has not
  /// closed yet would draw a ring past its own start.
  Duration remaining(DateTime now) {
    final Duration left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

/// What came back from tapping Accept (0148).
///
/// Three answers, and the middle one is the reason this is a type rather than a
/// `void`. Since a job stays on the board of every rider it was offered to,
/// two or three people can reach for the same order — and the platform's rule is
/// that the one nearest the restaurant gets it, not the one who tapped first.
/// So a *contested* accept opens a two-second window, collects everybody, and
/// then decides. The rider is asked to wait exactly that long and no longer.
///
/// An **uncontested** accept — which is nearly all of them, because during a
/// rider's own fifteen seconds nobody else has been asked yet — comes straight
/// back as [won] with nothing to wait for.
@immutable
class TakeOutcome {
  const TakeOutcome._(this.state, {this.decideAt, this.message});

  factory TakeOutcome.fromJson(Map<String, dynamic> json) {
    final String state = json['state'] as String? ?? 'none';
    final String? at = json['decide_at'] as String?;
    return TakeOutcome._(
      state,
      decideAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      message: json['message'] as String?,
    );
  }

  /// `won`, `pending`, `lost`, or — for an order this rider is not contesting at
  /// all — `none`. Compared through the getters below rather than read directly,
  /// so the database owns the vocabulary and the app owns none of it.
  final String state;

  /// When the contest closes, on this device's clock. Only ever set on
  /// [isPending], and the app waits until it before asking again.
  final DateTime? decideAt;

  /// The sentence to show a rider who lost, written server-side so it can be
  /// changed without a release.
  final String? message;

  bool get isWon => state == 'won';
  bool get isPending => state == 'pending';

  /// Anything that is not a win and not a wait. `lost` is the ordinary one;
  /// `none` means the contest was settled before this rider reached it, which
  /// reads the same way from a kerb.
  bool get isLost => !isWon && !isPending;

  /// How long is left to wait, floored at zero. A `pending` with no `decide_at`
  /// — which the database does not send, but a socket could truncate — waits the
  /// contest window rather than spinning for ever or resolving instantly.
  Duration waitFrom(DateTime now) {
    final DateTime? at = decideAt;
    if (at == null) return const Duration(seconds: 2);
    final Duration left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// One line of the thread with the customer waiting for this job (0061).
///
/// The customer app has the same class from the other side, and the only
/// difference between them is which value of `sender` counts as "mine". That
/// question is answered at parse time so the bubble never has to ask it.
@immutable
class JobMessage {
  const JobMessage({
    required this.id,
    required this.isMine,
    required this.body,
    required this.sentAt,
    required this.isRead,
  });

  factory JobMessage.fromJson(Map<String, dynamic> json) => JobMessage(
    id: (json['id'] as num).toInt(),
    isMine: json['sender'] == 'rider',
    body: json['body'] as String,
    sentAt: DateTime.parse(json['created_at'] as String).toLocal(),
    isRead: json['read_at'] != null,
  );

  final int id;
  final bool isMine;
  final String body;
  final DateTime sentAt;

  /// Whether the customer has opened the thread since this arrived. Only
  /// meaningful on a line of the rider's own.
  final bool isRead;
}

/// One sentence this rider may send, as the database words it.
///
/// Fetched rather than written here, and that is the point: 0061 owns the
/// wording, so the chip says exactly what will be stored. A second copy of the
/// list in this app is a list that will one day disagree with the one that
/// actually gets sent.
@immutable
class CannedMessage {
  const CannedMessage({required this.code, required this.body});

  factory CannedMessage.fromJson(Map<String, dynamic> json) => CannedMessage(
    code: json['code'] as String,
    body: json['body'] as String,
  );

  final String code;
  final String body;
}

/// One day's work, as `rider_earnings` counts it (migration 0043).
///
/// Only delivered jobs are in here. A job in hand has not been earned yet, and
/// a rider watching their total rise at pickup would have been told they were
/// paid for a delivery they might still fail to make. The day is the day it was
/// *delivered*, in IST — the day the rider actually worked.
@immutable
class EarningsDay {
  const EarningsDay({
    required this.day,
    required this.jobs,
    required this.earnings,
  });

  factory EarningsDay.fromJson(Map<String, dynamic> json) => EarningsDay(
    day: DateTime.parse(json['day'] as String),
    jobs: json['jobs'] as int? ?? 0,
    earnings: json['earnings'] as int? ?? 0,
  );

  /// A calendar date, not an instant. Deliberately not converted to local time:
  /// Postgres already resolved it to the rider's own day in IST, and calling
  /// `toLocal()` on a midnight date is how a day slides into the one before it.
  final DateTime day;

  final int jobs;
  final int earnings;
}

/// One week's pay, as a batch (migration 0045).
///
/// The rider's twin of a restaurant's settlement, and the same shape: a Mon–Sun
/// window, a count, an amount, and whether the money has actually left. Born in
/// the weekly rollup, marked paid by an admin with the bank's reference — never
/// by anything the rider does.
@immutable
class Payout {
  const Payout({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.deliveryCount,
    required this.grossAmount,
    required this.cashWithheld,
    required this.amount,
    required this.isPaid,
    required this.reference,
    required this.paidAt,
  });

  factory Payout.fromJson(Map<String, dynamic> json) => Payout(
    id: json['id'] as int,
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    deliveryCount: json['delivery_count'] as int? ?? 0,
    // Defaulted to `amount` for the batches struck before 0076 existed, where
    // the two were the same number by definition.
    grossAmount: json['gross_amount'] as int? ?? json['amount'] as int? ?? 0,
    cashWithheld: json['cash_withheld'] as int? ?? 0,
    amount: json['amount'] as int? ?? 0,
    isPaid: json['status'] == 'paid',
    reference: json['reference'] as String?,
    paidAt: json['paid_at'] == null
        ? null
        : DateTime.parse(json['paid_at'] as String).toLocal(),
  );

  final int id;

  /// Calendar dates, not instants — the same reasoning as [EarningsDay.day].
  final DateTime periodStart;
  final DateTime periodEnd;

  final int deliveryCount;

  /// What the week's deliveries earned, before COD cash was netted off (0076),
  /// and [cashWithheld] is how much of it was. Both are shown rather than only
  /// [amount]: a transfer that is smaller than the week's work without saying
  /// why is a rider who believes they were short-paid, and they would be right
  /// to ask.
  final int grossAmount;
  final int cashWithheld;

  final int amount;
  final bool isPaid;

  /// The bank's reference (a UTR), and the reason it is shown rather than kept
  /// for ops: a rider whose bank says nothing arrived needs the number to ask
  /// about, and asking the platform for it is a day lost.
  final String? reference;

  final DateTime? paidAt;
}

/// The platform's cash, in this rider's pocket right now (migration 0076).
///
/// [outstanding] is a sum over a ledger, never a stored balance: every COD
/// delivery adds the order total, every deposit and every weekly netting takes
/// it away. [cap] is what the platform is willing to be owed — past it, cash
/// jobs stop being offered and stop being claimable, so the number is only
/// useful next to the ceiling it is approaching.
@immutable
class CashInHand {
  const CashInHand({required this.outstanding, required this.cap});

  factory CashInHand.fromJson(Map<String, dynamic> json) => CashInHand(
    outstanding: json['outstanding'] as int? ?? 0,
    cap: json['cap'] as int? ?? 0,
  );

  final int outstanding;
  final int cap;

  /// How much more cash this rider may take on. Floored at zero — an adjustment
  /// can put somebody over the line, and "−₹200 of headroom" is not a sentence.
  int get headroom => outstanding >= cap ? 0 : cap - outstanding;

  /// Whether cash jobs have stopped. The app says so rather than letting the
  /// board quietly empty: a rider whose offers dried up needs to know it was the
  /// cash and not the evening.
  bool get isBlocked => outstanding >= cap;
}

/// A job this rider is actually carrying.
@immutable
class Job {
  const Job({
    required this.orderId,
    required this.state,
    required this.orderStatus,
    required this.restaurantName,
    required this.restaurantLat,
    required this.restaurantLng,
    required this.restaurantPhone,
    required this.deliverTo,
    required this.deliverLat,
    required this.deliverLng,
    required this.deliveryNotes,
    required this.customerPhone,
    // Optional, unlike its neighbours: it is genuinely absent on most jobs
    // until the route lookup lands, and defaulting it keeps every existing
    // caller compiling.
    this.routePolyline,
    required this.total,
    required this.isCash,
    required this.distanceKm,
    required this.payBase,
    required this.payPerKm,
    required this.riderPay,
    required this.claimedAt,
    required this.arrivedAtRestaurantAt,
    required this.arrivedAtCustomerAt,
    required this.deliveredAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    orderId: json['order_id'] as String,
    state: JobState.fromWire(json['state'] as String),
    orderStatus: json['order_status'] as String? ?? '',
    restaurantName: json['restaurant_name'] as String? ?? 'Restaurant',
    restaurantLat: (json['restaurant_lat'] as num?)?.toDouble(),
    restaurantLng: (json['restaurant_lng'] as num?)?.toDouble(),
    restaurantPhone: json['restaurant_phone'] as String?,
    deliverTo: json['deliver_to'] as String? ?? '',
    deliverLat: (json['deliver_lat'] as num?)?.toDouble(),
    deliverLng: (json['deliver_lng'] as num?)?.toDouble(),
    deliveryNotes: json['delivery_notes'] as String?,
    customerPhone: json['customer_phone'] as String? ?? '',
    routePolyline: json['route_polyline'] as String?,
    total: json['total'] as int? ?? 0,
    isCash: json['payment_method'] == 'cod',
    // `num`, not `int`: these are Postgres `numeric` and arrive as either,
    // depending on whether the value happens to be whole.
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
    payBase: json['pay_base'] as int? ?? 0,
    payPerKm: (json['pay_per_km'] as num?)?.toDouble() ?? 0,
    riderPay: json['rider_pay'] as int? ?? 0,
    claimedAt: DateTime.parse(json['claimed_at'] as String).toLocal(),
    arrivedAtRestaurantAt: _at(json['arrived_at_restaurant_at']),
    arrivedAtCustomerAt: _at(json['arrived_at_customer_at']),
    deliveredAt: _at(json['delivered_at']),
  );

  static DateTime? _at(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  final String orderId;
  final JobState state;

  /// The *order's* status, which is not the job's. Needed for one question the
  /// rider asks constantly while standing at a counter: is it packed yet?
  final String orderStatus;

  final String restaurantName;
  final String deliverTo;
  final String customerPhone;

  /// Both ends of the ride. Returned by `my_deliveries` since 0025 and ignored
  /// by this app until navigation arrived — the restaurant's are null for any
  /// kitchen without a map location on file (see 0042, and seed 0007 for the
  /// eight demo ones), and a null pair means the map gets the address text
  /// instead of a pin.
  final double? restaurantLat;
  final double? restaurantLng;
  final double? deliverLat;
  final double? deliverLng;

  /// The kitchen's own number (0027, handed over by `my_deliveries` since 0061).
  /// Null on every seeded restaurant and on any an admin has not filled in — and
  /// a null here means no Call button rather than a dialler opening on nothing.
  /// The one question it answers is the one a rider asks at a counter with
  /// nobody behind it: *is anyone making this?*
  final String? restaurantPhone;

  /// What the customer said about their own front door — "gate 2, blue
  /// building". Null when they said nothing, and withheld once the job is
  /// delivered, exactly as [customerPhone] is: the note describes where somebody
  /// lives, and the job is over.
  final String? deliveryNotes;

  /// Where this job is going *right now* — the kitchen until it is collected,
  /// the customer after. The one question a navigation button has to answer,
  /// and answering it from [state] means the rider never picks the wrong end.
  /// The road from the kitchen to the door, encoded, as Ola drew it (0046) and
  /// `my_deliveries` now returns (0059). Null until the route lookup comes back
  /// — the in-app map is then framed on the two pins with no line between them,
  /// which is what we actually know at that moment.
  final String? routePolyline;

  double? get targetLat => isCarrying ? deliverLat : restaurantLat;
  double? get targetLng => isCarrying ? deliverLng : restaurantLng;
  String get targetLabel => isCarrying ? deliverTo : restaurantName;

  /// Who the Call button rings, which is whichever end of the ride the rider is
  /// at — the same rule the map pin follows, so the two can never point at
  /// different people. Null when that end has no number on file, and the button
  /// is then absent rather than dead.
  String? get targetPhone => isCarrying
      ? (customerPhone.isEmpty ? null : customerPhone)
      : restaurantPhone;

  /// What to call them, for the button's label and its confirmation.
  String get targetWho => isCarrying ? 'Customer' : 'Restaurant';
  final int total;
  final bool isCash;

  /// Straight-line kilometres from the kitchen to the door, as measured when
  /// the job was claimed — **null when it could not be measured at all**,
  /// which means the restaurant has no coordinates on file. Null is not zero,
  /// and the difference is visible to the rider: an unmeasured job pays the
  /// base fee and says so, rather than showing a confident `0.0 km`.
  final double? distanceKm;

  /// The two halves of the rate that applied *at claim time* (migration 0043).
  /// Kept apart from [riderPay] rather than folded into it so a rider can check
  /// the arithmetic — pay you cannot check is pay you will eventually dispute.
  final int payBase;
  final double payPerKm;

  /// What this job pays, in whole rupees. Earned on delivery, not on claim.
  final int riderPay;

  final DateTime claimedAt;

  /// When the rider said they were there. The kitchen's screen counts up from
  /// [arrivedAtRestaurantAt] — "waiting 9 min" is only honest because this is a
  /// recorded fact rather than an inference from the claim time.
  final DateTime? arrivedAtRestaurantAt;
  final DateTime? arrivedAtCustomerAt;
  final DateTime? deliveredAt;

  /// Whether the kitchen has finished. Until this is true there is no code to
  /// type, because there is nothing on the counter to hand over.
  bool get isReadyToCollect => orderStatus == 'ready_for_pickup';

  /// Carrying, in the map sense: heading for the customer rather than the
  /// kitchen. True from pickup onward, including while standing at the door.
  bool get isCarrying =>
      state == JobState.pickedUp || state == JobState.arrivedAtCustomer;

  /// What this rider is expected to do next, which is exactly one thing.
  JobStep get step => switch (state) {
    JobState.claimed => JobStep.rideToRestaurant,
    JobState.arrivedAtRestaurant => JobStep.collect,
    JobState.pickedUp => JobStep.rideToCustomer,
    JobState.arrivedAtCustomer => JobStep.handOver,
    JobState.delivered || JobState.cancelled => JobStep.done,
  };

  /// The sum, spelled out: "₹25 + 4.2 km × ₹5".
  ///
  /// The unmeasured case says what actually happened rather than hiding it —
  /// a rider who reads "base fee only" and knows the ride was six kilometres
  /// has been handed the exact sentence to complain with, which is the point.
  String get payExplained => distanceKm == null
      ? '₹$payBase base fee only — this kitchen has no map location'
      : '₹$payBase + ${_trim(distanceKm!)} km × ₹${_trim(payPerKm)}';

  /// 4.20 → "4.2", 5.00 → "5". Trailing zeros on money a rider is reading at a
  /// traffic light are noise.
  static String _trim(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
