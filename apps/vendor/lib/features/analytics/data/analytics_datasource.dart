import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';

/// The kitchen's read-only window onto what it sold.
///
/// One method, one RPC. Like Payments, analytics is a subscriber to figures
/// Postgres computes (`vendor_analytics`, 0019), never a writer of them.
abstract interface class AnalyticsDataSource {
  /// What the restaurant sold between [from] and [to], inclusive — totals, the
  /// best-sellers, and order volume by hour. Computed live, so it is current.
  Future<AnalyticsSummary> fetch({required DateTime from, required DateTime to});
}

class AnalyticsSupabaseDataSource implements AnalyticsDataSource {
  const AnalyticsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// The RPC takes `date`, so only the calendar day travels — never a time or
  /// a zone. Same shape as the earnings source (0017).
  static String _asDate(DateTime d) {
    final String m = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  @override
  Future<AnalyticsSummary> fetch({
    required DateTime from,
    required DateTime to,
  }) async {
    final Map<String, dynamic> json = await _db.rpc<Map<String, dynamic>>(
      'vendor_analytics',
      params: <String, dynamic>{'p_from': _asDate(from), 'p_to': _asDate(to)},
    );
    return AnalyticsSummary.fromJson(json);
  }
}
