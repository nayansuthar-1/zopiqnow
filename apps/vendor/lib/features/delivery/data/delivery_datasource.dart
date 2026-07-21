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
        .select('order_id, state, pickup_otp, delivery_partners(name, phone)')
        .inFilter('state', <String>['claimed', 'picked_up']);

    return <String, OrderDelivery>{
      for (final Map<String, dynamic> row in rows)
        row['order_id'] as String: OrderDelivery.fromJson(row),
    };
  }
}
