import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/core/observability/crash_reporter.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_invoice.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_message.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

/// Orders and coupons, over the `validate_coupon` and `place_order` functions.
///
/// The tables behind them are invisible to this key — RLS is on with no select
/// policy — so these two functions are the entire surface. Everything the
/// customer is charged is decided inside them.
class OrderSupabaseDataSource implements OrderDataSource {
  const OrderSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Postgres raises `P0001` for the rules we wrote, with a message written for
  /// the customer. Any other code is a bug or an outage — not something to put
  /// in front of a human.
  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<AppliedCoupon> applyCoupon({
    required String code,
    required int subtotal,
    required String restaurantId,
  }) async {
    try {
      // All three arguments, every time. `p_restaurant_id` is defaulted in the
      // database so that an old build still binds to this signature — which is
      // what kept a restaurant's own offer failing here silently rather than
      // erroring. `place_order` has always passed it; the preview had not, so
      // the two disagreed about what a valid code was.
      final dynamic discount = await _db.rpc<dynamic>(
        'validate_coupon',
        params: <String, dynamic>{
          'p_code': code,
          'p_subtotal': subtotal,
          'p_restaurant_id': restaurantId,
        },
      );
      return AppliedCoupon(
        code: code.trim().toUpperCase(),
        discount: (discount as num).toInt(),
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw CouponFailure(e.message);
      rethrow;
    }
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
    String? idempotencyKey,
  }) async {
    try {
      // The session's JWT rides along on the RPC, and `place_order` takes the
      // buyer from `auth.uid()`. That is why no user id is sent: the one value
      // the client must not be trusted with is who it is.
      final Map<String, dynamic> receipt = await _db
          .rpc<Map<String, dynamic>>(
            'place_order',
            params: <String, dynamic>{
              'p_user_phone': userPhone,
              'p_restaurant_id': cart.restaurantId,
              // Ids, quantities and the chosen option ids only. No prices leave
              // this device — place_order re-prices every line and its options.
              'p_items': cart.lines
                  .map(
                    (CartLine l) => <String, dynamic>{
                      'menu_item_id': l.item.id,
                      'quantity': l.quantity,
                      'option_ids': l.options
                          .map((MenuOption o) => o.id)
                          .toList(),
                    },
                  )
                  .toList(),
              'p_delivery_to': deliveryAddress.shortDisplay,
              'p_delivery_lat': deliveryAddress.latitude,
              'p_delivery_lng': deliveryAddress.longitude,
              'p_payment_method': paymentMethod.name,
              'p_coupon_code': couponCode,
              'p_payment_id': paymentId,
              'p_delivery_notes': deliveryNotes,
              // The one parameter whose whole purpose is to be sent *again*.
              // 0086 answers a key it has already seen with the order it
              // already placed, so a retry after a lost response is safe.
              'p_idempotency_key': idempotencyKey,
            },
          );

      return PlacedOrder(
        id: receipt['id'] as String,
        restaurantName: receipt['restaurant_name'] as String,
        deliveryTo: receipt['delivery_to'] as String,
        total: (receipt['total'] as num).toInt(),
        paymentMethod: paymentMethod,
        etaMinutes: (receipt['eta_minutes'] as num).toInt(),
        paymentId: receipt['payment_id'] as String?,
      );
    } on PostgrestException catch (e, stack) {
      // "Your cart is empty", "Something in your cart is no longer available" —
      // rules we wrote, phrased for the customer, so they are worth showing.
      if (e.code == _businessRuleErrorCode) {
        throw OrderPlacementFailure(e.message);
      }

      // **This line is why crash reporting exists** (launch C3, audit OBS-001).
      //
      // On 29 July it swallowed SQLSTATE 21000 — `pg_safeupdate` refusing the
      // `where`-less update 0078 had just added to `place_order` — and handed
      // the customer "We couldn't place your order. Please try again." Nobody
      // could order anything for three days and the real code was written down
      // nowhere. It was found because somebody happened to try, which is not a
      // monitoring strategy.
      //
      // The rule this establishes: when the app replaces the truth with a
      // friendlier sentence, the truth goes here first.
      CrashReporter.recordHandled(
        e,
        stack,
        reason: 'place_order failed with ${e.code ?? 'no code'}',
      );
      throw const OrderPlacementFailure();
    }
  }

  /// How far back "your orders" goes. A customer with a thousand orders does not
  /// want a thousand cards, and an unbounded select is how a screen that was
  /// fast in testing gets slow in production. Paging arrives if anyone asks.
  static const int _historyLimit = 25;

  /// Everything an order renders from. One constant, because the list and the
  /// detail screen show the same order and a column the detail screen forgot to
  /// ask for is a field that is null on exactly one of them.
  static const String _orderColumns =
      'id, restaurant_id, restaurant_name, status, status_reason, created_at, '
      'delivery_to, delivery_notes, eta_minutes, payment_method, payment_id, '
      'subtotal, delivery_fee, platform_fee, packaging_fee, surge_fee, '
      'taxes, discount, total, coupon_code, '
      // The catalog join is for the photo and the kitchen's phone number — the
      // name is on the order, so a delisted restaurant costs us an image and a
      // number, not an identity. `contact_phone` has been world-readable on an
      // active restaurant since 0027; showing it only here is a product choice.
      'restaurants(image_url, contact_phone), '
      'order_items(menu_item_id, name, unit_price, quantity, line_total, '
      'order_item_options(name, price_delta))';

  @override
  Future<List<CustomerOrder>> fetchOrders() async {
    // No `.eq('user_id', …)`. The row-level policy on `orders` already answers
    // "whose?" from the JWT, and a filter here would only be a second, weaker
    // copy of that rule — one that a bug could get wrong and that an attacker
    // could simply omit.
    final List<Map<String, dynamic>> rows = await _db
        .from('orders')
        .select(_orderColumns)
        .order('created_at', ascending: false)
        .limit(_historyLimit);

    return rows.map(_orderFrom).toList(growable: false);
  }

  @override
  Future<CustomerOrder?> fetchOrder(String orderId) async {
    // `maybeSingle`, not `single`: an order that isn't there is an answer, not
    // an exception. The policy makes "someone else's order" indistinguishable
    // from "no such order", which is the behaviour we want anyway.
    final Map<String, dynamic>? row = await _db
        .from('orders')
        .select(_orderColumns)
        .eq('id', orderId)
        .maybeSingle();

    return row == null ? null : _orderFrom(row);
  }

  @override
  Stream<OrderStatus> watchOrderStatus(String orderId) {
    // `.stream()` selects the row and then holds a Realtime subscription open,
    // so the first event is the status as it stands and every later one is a
    // write to the row. Only the status is read off it — the rest of the order
    // is immutable once `place_order` has written it, and re-parsing a whole
    // receipt on every kitchen update would be work for a field that cannot
    // have changed.
    return _db
        .from('orders')
        .stream(primaryKey: const <String>['id'])
        .eq('id', orderId)
        // An empty list means the row is gone or was never ours. There is no
        // status to report, so report none rather than inventing one.
        .where((List<Map<String, dynamic>> rows) => rows.isNotEmpty)
        .map(
          (List<Map<String, dynamic>> rows) =>
              OrderStatus.fromWire(rows.first['status'] as String),
        );
  }

  @override
  Future<OrderRider?> fetchRider(String orderId) async {
    // Two policies do the whole job (migration 0039): the delivery is readable
    // only by the customer whose order it is, and only while `picked_up`, and
    // the partner row only by way of such a delivery. So there is no state
    // filter and no user filter here — a `.eq('state', …)` would be a second,
    // weaker copy of a rule Postgres already enforces, and one the next reader
    // would have to be told not to trust.
    final Map<String, dynamic>? row = await _db
        .from('deliveries')
        .select('state, partner_email, delivery_partners(name, phone, vehicle)')
        .eq('order_id', orderId)
        .maybeSingle();

    final Map<String, dynamic>? partner =
        row?['delivery_partners'] as Map<String, dynamic>?;
    if (partner == null) return null;

    return OrderRider(
      name: partner['name'] as String,
      phone: partner['phone'] as String,
      vehicle: partner['vehicle'] as String,
      isAtDoor: row!['state'] == 'arrived_at_customer',
      // Read from the same row for free. See [OrderRider.carrierKey] — a
      // subscription filter, not a credential.
      carrierKey: row['partner_email'] as String?,
    );
  }

  /// The map's fixed parts, in one call (migration 0057).
  ///
  /// An RPC rather than a select, for the reason `order_delivery_code` is one:
  /// it returns the *restaurant's* coordinates, which a customer has no policy
  /// to read in bulk. The function scopes the answer to one order that belongs
  /// to the caller and hands back nothing else.
  @override
  Future<DeliveryRoute?> fetchRoute(String orderId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'order_route',
      params: <String, dynamic>{'p_order_id': orderId},
    );
    if (rows.isEmpty) return null;
    return DeliveryRoute.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Stream<RiderPosition?> watchRiderPosition(String carrierKey) {
    // The `.eq` is not the security boundary — the 0057 policy is, and returns
    // nothing at all for a rider who is not carrying this customer's food. It
    // is here so the socket carries one row rather than being asked to.
    return _db
        .from('rider_locations')
        .stream(primaryKey: const <String>['partner_email'])
        .eq('partner_email', carrierKey)
        .map(
          (List<Map<String, dynamic>> rows) => rows.isEmpty
              // Not an error: the rider has not reported yet, or the job ended
              // and 0057's purge took the row. Both mean "no dot on the map".
              ? null
              : RiderPosition.fromJson(rows.first),
        );
  }

  /// The four digits the customer reads out at the door (0049).
  ///
  /// An RPC, unlike everything else on this screen, because the code is the one
  /// thing here that must not be a column: the rider holds a select policy on
  /// their own delivery row, so a code stored there would be a code they could
  /// look up instead of being told. `order_delivery_code` answers the order's
  /// own customer and nobody else, and only while it is out for delivery.
  @override
  Future<String?> fetchDeliveryCode(String orderId) async {
    try {
      return await _db.rpc<String>(
        'order_delivery_code',
        params: <String, dynamic>{'p_order_id': orderId},
      );
    } on PostgrestException {
      // Not out for delivery yet, or no longer. Not an error the customer needs
      // to see — the code simply is not on screen.
      return null;
    }
  }

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) async {
    try {
      await _db.rpc<String>(
        'cancel_my_order',
        params: <String, dynamic>{'p_order_id': orderId, 'p_reason': reason},
      );
    } on PostgrestException catch (e) {
      // "The kitchen has already started cooking this order." — a rule we wrote,
      // phrased for the customer, and the most useful sentence on the screen at
      // that moment. Anything else is an outage, and gets the generic apology.
      if (e.code == _businessRuleErrorCode) throw OrderCancelFailure(e.message);
      throw const OrderCancelFailure();
    }
  }

  @override
  Future<List<CannedMessage>> fetchMessageMenu() async {
    // No argument. `order_message_menu` derives the role from the caller — a
    // customer asking for the rider's half of the list gets their own.
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'order_message_menu',
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(CannedMessage.fromJson)
        .toList(growable: false);
  }

  @override
  Stream<List<OrderMessage>> watchMessages(String orderId) {
    return _db
        .from('order_messages')
        .stream(primaryKey: const <String>['id'])
        .eq('order_id', orderId)
        // Oldest first: a thread reads downward, and the sheet scrolls to the
        // bottom. `.order` on a stream sorts the snapshot it holds, which is
        // why the list arrives ordered rather than in insert order.
        .order('created_at', ascending: true)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(OrderMessage.fromJson).toList(growable: false),
        );
  }

  @override
  Future<void> sendMessage({
    required String orderId,
    required String code,
  }) async {
    try {
      await _db.rpc<int>(
        'send_order_message',
        params: <String, dynamic>{'p_order_id': orderId, 'p_code': code},
      );
    } on PostgrestException catch (e) {
      // "There is nobody on this order to message right now." — the rider handed
      // the food over while the sheet was open. A rule we wrote, phrased for the
      // customer, and the only useful thing to say at that moment.
      if (e.code == _businessRuleErrorCode) throw OrderMessageFailure(e.message);
      throw const OrderMessageFailure();
    }
  }

  @override
  Future<void> markMessagesRead(String orderId) async {
    try {
      await _db.rpc<void>(
        'mark_order_messages_read',
        params: <String, dynamic>{'p_order_id': orderId},
      );
    } on PostgrestException {
      // A read receipt nobody got. Swallowed on purpose — there is nothing the
      // customer could do about it and nothing worth interrupting them for.
    }
  }

  CustomerOrder _orderFrom(Map<String, dynamic> row) {
    final Map<String, dynamic>? restaurant =
        row['restaurants'] as Map<String, dynamic>?;

    final List<OrderLine> lines =
        (row['order_items'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> i) => OrderLine(
                menuItemId: i['menu_item_id'] as String,
                name: i['name'] as String,
                unitPrice: (i['unit_price'] as num).toInt(),
                quantity: (i['quantity'] as num).toInt(),
                lineTotal: (i['line_total'] as num).toInt(),
                options:
                    (i['order_item_options'] as List<dynamic>? ??
                            const <dynamic>[])
                        .cast<Map<String, dynamic>>()
                        .map((Map<String, dynamic> o) => o['name'] as String)
                        .toList(growable: false),
              ),
            )
            .toList()
          // PostgREST does not promise an order within an embedded list, and a
          // receipt whose lines shuffle between two reads of the same order
          // looks broken. Sorting by name is arbitrary but stable.
          ..sort((OrderLine a, OrderLine b) => a.name.compareTo(b.name));

    return CustomerOrder(
      id: row['id'] as String,
      restaurantId: row['restaurant_id'] as String,
      restaurantName: row['restaurant_name'] as String,
      restaurantImageUrl: restaurant?['image_url'] as String? ?? '',
      // Null on every seeded restaurant and on any draft an admin has not
      // finished (0027). Null means no Call button, which beats a dialler
      // opening on an empty number.
      restaurantPhone: restaurant?['contact_phone'] as String?,
      status: OrderStatus.fromWire(row['status'] as String),
      statusReason: row['status_reason'] as String?,
      placedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      deliveryTo: row['delivery_to'] as String,
      deliveryNotes: row['delivery_notes'] as String?,
      etaMinutes: (row['eta_minutes'] as num).toInt(),
      paymentMethod: PaymentMethod.values.byName(row['payment_method'] as String),
      paymentId: row['payment_id'] as String?,
      subtotal: (row['subtotal'] as num).toInt(),
      deliveryFee: (row['delivery_fee'] as num).toInt(),
      platformFee: (row['platform_fee'] as num?)?.toInt() ?? 0,
      packagingFee: (row['packaging_fee'] as num?)?.toInt() ?? 0,
      surgeFee: (row['surge_fee'] as num?)?.toInt() ?? 0,
      taxes: (row['taxes'] as num).toInt(),
      discount: (row['discount'] as num).toInt(),
      total: (row['total'] as num).toInt(),
      couponCode: row['coupon_code'] as String?,
      lines: lines,
    );
  }

  /// An RPC rather than the select this used to be (migration 0064).
  ///
  /// `coupons` is no longer world-readable in full: a restaurant's own offer is
  /// visible on that restaurant's page and nowhere else, so a customer browsing
  /// the app cannot pull down every promotion every kitchen is running. The
  /// function returns this restaurant's offers *and* the platform's, already
  /// worded, already ordered.
  @override
  Future<List<RestaurantOffer>> fetchOffers(String restaurantId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'restaurant_offers',
      params: <String, dynamic>{'p_restaurant_id': restaurantId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(RestaurantOffer.fromJson)
        .toList(growable: false);
  }

  @override
  Future<OrderReviewState> fetchReviewState(String orderId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'order_review_state',
      params: <String, dynamic>{'p_order_id': orderId},
    );
    // No row is a real answer and the commonest one: the order is still open,
    // or belongs to somebody else. Both mean there is nothing to rate.
    if (rows.isEmpty) return OrderReviewState.none;
    return OrderReviewState.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<List<OrderRefund>> fetchRefunds(String orderId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'my_order_refund',
      params: <String, dynamic>{'p_order_id': orderId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(OrderRefund.fromJson)
        .toList(growable: false);
  }

  @override
  Future<OrderReview?> fetchMyReview(String orderId) async {
    final List<dynamic> rows = await _db.rpc<List<dynamic>>(
      'my_order_review',
      params: <String, dynamic>{'p_order_id': orderId},
    );
    if (rows.isEmpty) return null;
    return OrderReview.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<void> submitReview({
    required String orderId,
    required int foodRating,
    int? riderRating,
    String? comment,
  }) async {
    try {
      await _db.rpc<void>(
        'submit_order_review',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_food_rating': foodRating,
          'p_rider_rating': riderRating,
          'p_comment': comment,
        },
      );
    } on PostgrestException catch (e) {
      // "This review can no longer be changed." / "This order is too old to
      // review." — rules we wrote, phrased for the customer, and the only
      // useful thing to say at that moment.
      if (e.code == _businessRuleErrorCode) throw OrderReviewFailure(e.message);
      throw const OrderReviewFailure();
    }
  }

  @override
  Future<OrderInvoice> fetchInvoice(String orderId) async {
    try {
      final Map<String, dynamic> doc = await _db.rpc<Map<String, dynamic>>(
        'order_invoice',
        params: <String, dynamic>{'p_order_id': orderId},
      );
      return OrderInvoice.fromJson(doc);
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw InvoiceFailure(e.message);
      throw const InvoiceFailure();
    }
  }
}
