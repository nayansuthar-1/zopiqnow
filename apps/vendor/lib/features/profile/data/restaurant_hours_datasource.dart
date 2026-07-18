import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/profile/domain/entities/opening_hours.dart';

/// The vendor's read and write of its own opening hours.
///
/// Reading is a plain select against `restaurant_hours` (world-readable for an
/// active restaurant, 0018). Writing is the RPC and only the RPC — there is no
/// insert/update/delete grant on the table for a vendor; `set_restaurant_hours`
/// replaces the whole week in one transaction.
abstract interface class RestaurantHoursDataSource {
  Future<List<OpeningHours>> fetch(String restaurantId);

  /// Replace the week. [hours] holds only the open days, in any order.
  Future<void> save(List<OpeningHours> hours);
}

/// A write the database refused — a validation rule (`P0001`) or an outage.
class HoursWriteFailure implements Exception {
  const HoursWriteFailure([
    this.message = 'We couldn\'t save your hours. Please try again.',
  ]);

  final String message;
}

class RestaurantHoursSupabaseDataSource implements RestaurantHoursDataSource {
  const RestaurantHoursSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<List<OpeningHours>> fetch(String restaurantId) async {
    final List<Map<String, dynamic>> rows = await _db
        .from('restaurant_hours')
        .select('day_of_week, opens, closes')
        .eq('restaurant_id', restaurantId)
        .order('day_of_week', ascending: true);

    return rows.map(OpeningHours.fromRow).toList(growable: false);
  }

  @override
  Future<void> save(List<OpeningHours> hours) async {
    try {
      await _db.rpc<void>(
        'set_restaurant_hours',
        params: <String, dynamic>{
          'p_hours': hours.map((OpeningHours h) => h.toJson()).toList(),
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw HoursWriteFailure(e.message);
      throw const HoursWriteFailure();
    }
  }
}
