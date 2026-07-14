import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';

/// The kitchen's view of the order book.
abstract interface class VendorOrderDataSource {
  /// Every order at this restaurant, live, oldest first.
  ///
  /// Includes finished ones — filtering happens above, because "the queue" and
  /// "today's orders" are two readings of the same stream and one subscription
  /// is cheaper than two.
  Stream<List<VendorOrder>> watchOrders(String restaurantId);

  /// The lines of one order. Fetched separately from the stream, and separately
  /// *because* of it: Realtime publishes row changes on a single table and does
  /// not do joins, so the embedded read that the customer's history uses is not
  /// available here. It costs nothing — an order's lines are written once by
  /// `place_order` and never change, so one fetch per order is one fetch, ever.
  Future<List<OrderLine>> fetchLines(String orderId);

  /// Moves the order on. Throws [OrderStatusFailure] with the database's own
  /// sentence when the move is not allowed.
  Future<OrderStatus> setStatus({
    required String orderId,
    required OrderStatus status,
  });
}

/// A move the order service refused. The message is written for the person
/// holding the tablet — "An order that is delivered cannot become preparing" —
/// so the ticket shows it rather than a generic apology.
class OrderStatusFailure implements Exception {
  const OrderStatusFailure([
    this.message = 'We couldn\'t update that order. Please try again.',
  ]);

  final String message;

  @override
  String toString() => 'OrderStatusFailure: $message';
}

class VendorOrderSupabaseDataSource implements VendorOrderDataSource {
  const VendorOrderSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// Postgres raises `P0001` for the rules we wrote, with a message written for
  /// a human. Any other code is a bug or an outage.
  static const String _businessRuleErrorCode = 'P0001';

  @override
  Stream<List<VendorOrder>> watchOrders(String restaurantId) {
    // The `.eq` is not the security boundary — the RLS policy from 0009 is, and
    // it would return nothing for a restaurant this user does not work at even
    // if the id here were tampered with. This filter is here so the socket
    // carries one kitchen's orders instead of every kitchen's.
    return _db
        .from('orders')
        .stream(primaryKey: const <String>['id'])
        .eq('restaurant_id', restaurantId)
        // Oldest first. A queue is a queue: the ticket that has been waiting
        // longest is the one that needs a person, and putting the newest on top
        // is how the oldest one starves.
        .order('created_at', ascending: true)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(_orderFrom).toList(growable: false),
        );
  }

  @override
  Future<List<OrderLine>> fetchLines(String orderId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('order_items')
        .select('name, quantity, line_total')
        .eq('order_id', orderId)
        // PostgREST promises no order without one, and a ticket whose lines
        // shuffle between two reads is a ticket a cook re-reads from the top.
        .order('name', ascending: true);

    return rows
        .map(
          (Map<String, dynamic> r) => OrderLine(
            name: r['name'] as String,
            quantity: (r['quantity'] as num).toInt(),
            lineTotal: (r['line_total'] as num).toInt(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<OrderStatus> setStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    try {
      // An id and a status. Not an order — there is no update grant on `orders`
      // at all, so this function is the only way a vendor can write to one, and
      // the only column it can reach is `status` (migration 0009). A restaurant
      // that could `update` the row could edit the total of an order the
      // customer has already agreed to.
      final String written = await _db.rpc<String>(
        'set_order_status',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_status': status.wire,
        },
      );
      return OrderStatus.fromWire(written);
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw OrderStatusFailure(e.message);
      throw const OrderStatusFailure();
    }
  }

  VendorOrder _orderFrom(Map<String, dynamic> row) => VendorOrder(
    id: row['id'] as String,
    status: OrderStatus.fromWire(row['status'] as String),
    placedAt: DateTime.parse(row['created_at'] as String).toLocal(),
    customerPhone: row['user_phone'] as String,
    deliveryTo: row['delivery_to'] as String,
    total: (row['total'] as num).toInt(),
    paymentMethod: PaymentMethod.fromWire(row['payment_method'] as String),
  );
}
