import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/settlement.dart';

/// The kitchen's read-only window onto its money.
///
/// Every method here reads; none writes. The vendor is the party being paid, and
/// the party being paid does not set what it is paid — the figures are computed
/// or rolled up in Postgres (`0017`), and this is a subscriber to them.
abstract interface class PaymentsDataSource {
  /// What the restaurant earned between [from] and [to], inclusive — totals plus
  /// a per-day series. Computed live from delivered orders, so it is current.
  Future<EarningsSummary> fetchEarnings({
    required DateTime from,
    required DateTime to,
  });

  /// The payout batches, newest week first.
  Future<List<Settlement>> fetchSettlements();

  /// The delivered orders inside one batch — the statement's line items.
  Future<List<SettlementOrder>> fetchSettlementOrders(int settlementId);
}

class PaymentsSupabaseDataSource implements PaymentsDataSource {
  const PaymentsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// The database dates on whole days; the RPC takes `date`, so only the
  /// calendar day travels, never a time or a zone.
  static String _asDate(DateTime d) {
    final String m = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  @override
  Future<EarningsSummary> fetchEarnings({
    required DateTime from,
    required DateTime to,
  }) async {
    final Map<String, dynamic> json = await _db.rpc<Map<String, dynamic>>(
      'vendor_earnings_summary',
      params: <String, dynamic>{'p_from': _asDate(from), 'p_to': _asDate(to)},
    );
    return EarningsSummary.fromJson(json);
  }

  @override
  Future<List<Settlement>> fetchSettlements() async {
    // No `.eq('restaurant_id', …)`: the 0017 RLS policy already returns only
    // this vendor's settlements, and there is nothing else to narrow by.
    final List<Map<String, dynamic>> rows = await _db
        .from('settlements')
        .select(
          'id, period_start, period_end, order_count, gross_sales, '
          'commission, net_payable, status, reference, created_at, paid_at',
        )
        .order('period_end', ascending: false);

    return rows.map(Settlement.fromJson).toList(growable: false);
  }

  @override
  Future<List<SettlementOrder>> fetchSettlementOrders(int settlementId) async {
    // Readable under the 0009 orders policy; filtered to the batch. The vendor
    // can only ever name a `settlement_id` that is theirs, and even a guessed one
    // returns nothing for a batch at another restaurant.
    final List<Map<String, dynamic>> rows = await _db
        .from('orders')
        .select('id, created_at, subtotal')
        .eq('settlement_id', settlementId)
        .order('created_at', ascending: false);

    return rows
        .map(
          (Map<String, dynamic> r) => SettlementOrder(
            id: r['id'] as String,
            placedAt: DateTime.parse(r['created_at'] as String).toLocal(),
            gross: (r['subtotal'] as num).toInt(),
          ),
        )
        .toList(growable: false);
  }
}
