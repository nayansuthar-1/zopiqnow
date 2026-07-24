import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/delivery/domain/entities/order_delivery.dart';

/// The kitchen's read of who is carrying its orders.
///
/// A plain select, not an RPC, because there is nothing to guard beyond which
/// rows come back — and the 0025 policies already answer that: a vendor sees
/// deliveries whose order belongs to their restaurant, and the rider behind one
/// only while it is live.
abstract interface class DeliveryDataSource {
  /// Every live delivery at this restaurant, keyed by order id.
  Future<Map<String, OrderDelivery>> fetchActive();

  /// The four digits to read across the counter, fetched per order.
  ///
  /// A call rather than a column: 0049 moved the codes off `deliveries` because
  /// the rider can select their own row there, which made the code they were
  /// meant to be told something they could simply look up. `order_pickup_code`
  /// answers a staff member of that order's restaurant and nobody else.
  Future<String> pickupCode(String orderId);

  /// A new code after five wrong guesses locked the old one. Safe in the hands
  /// that read it out — they already know it.
  Future<String> reissuePickupCode(String orderId);
}

/// A refusal from 0049 (`P0001`), whose sentences are already written for a
/// human — "No rider is waiting on that order."
class DeliveryFailure implements Exception {
  const DeliveryFailure([this.message = 'Something went wrong. Please try again.']);

  final String message;
}

class DeliverySupabaseDataSource implements DeliveryDataSource {
  const DeliverySupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<Map<String, OrderDelivery>> fetchActive() async {
    // The embedded `delivery_partners` is PostgREST following the foreign key on
    // `partner_email` — one round trip for the job and the person doing it. Both
    // sides are policy-scoped independently, so the embed cannot widen either.
    final List<Map<String, dynamic>> rows = await _db
        .from('deliveries')
        .select(
          'order_id, state, arrived_at_restaurant_at, '
          'delivery_partners(name, phone)',
        )
        .inFilter('state', <String>[
          'claimed',
          'arrived_at_restaurant',
          'picked_up',
          'arrived_at_customer',
        ]);

    return <String, OrderDelivery>{
      for (final Map<String, dynamic> row in rows)
        row['order_id'] as String: OrderDelivery.fromJson(row),
    };
  }

  @override
  Future<String> pickupCode(String orderId) =>
      _guard(() => _db.rpc<String>(
        'order_pickup_code',
        params: <String, dynamic>{'p_order_id': orderId},
      ));

  @override
  Future<String> reissuePickupCode(String orderId) =>
      _guard(() => _db.rpc<String>(
        'regenerate_pickup_code',
        params: <String, dynamic>{'p_order_id': orderId},
      ));

  Future<String> _guard(Future<String> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw DeliveryFailure(e.message);
      throw const DeliveryFailure();
    }
  }
}
