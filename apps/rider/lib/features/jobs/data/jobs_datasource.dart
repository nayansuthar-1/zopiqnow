import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

/// Everything a rider can do, which is six functions and no table writes.
///
/// Every one of these is an RPC, and that is the whole security design of this
/// app rather than an implementation detail: migration 0025 gave riders **no
/// policy on `orders` at all**. A rider cannot select an order, ever. They call
/// a `security definer` function that returns a fixed set of named columns for
/// jobs they are entitled to, and nothing else in the database is reachable.
abstract interface class JobsDataSource {
  /// Cooked-or-nearly orders that nobody has claimed.
  Future<List<JobOffer>> fetchBoard();

  /// This rider's own jobs, live ones first.
  Future<List<Job>> fetchMine();

  /// Take a job. Refuses if someone else got there first.
  Future<void> claim(String orderId);

  /// Put an unstarted job back on the board.
  Future<void> abandon(String orderId);

  /// I'm at the restaurant. Required before [confirmPickup] — Postgres refuses
  /// a pickup straight from `claimed` (0049), so this is a step, not a courtesy.
  Future<void> arriveAtRestaurant(String orderId);

  /// Collect the bag, proving it with the code the restaurant reads out.
  Future<void> confirmPickup({required String orderId, required String otp});

  /// I'm at the door. Required before [confirmDelivered], same as above.
  Future<void> arriveAtCustomer(String orderId);

  /// Hand it over, proving it with the code the *customer* reads out.
  Future<void> confirmDelivered({required String orderId, required String otp});

  /// Whether this rider is on shift right now.
  Future<bool> fetchOnline();

  /// Start or end a shift. Refused while carrying anything (0049).
  Future<void> setOnline(bool online);

  /// What this rider earned, by day, over a closed date range.
  ///
  /// A separate call rather than totalling [fetchMine], which returns every job
  /// the rider has ever held: an earnings screen that downloads a career to
  /// display a week gets slower every shift.
  Future<List<EarningsDay>> fetchEarnings({
    required DateTime from,
    required DateTime to,
  });

  /// This rider's weekly pay batches, newest first.
  Future<List<Payout>> fetchPayouts();
}

/// A call the database refused — a rule in 0025 (`P0001`: somebody else claimed
/// it, the food is not packed, the code is wrong) or an outage.
class JobFailure implements Exception {
  const JobFailure([this.message = 'Something went wrong. Please try again.']);

  final String message;
}

class JobsSupabaseDataSource implements JobsDataSource {
  const JobsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<List<JobOffer>> fetchBoard() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('available_deliveries'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(JobOffer.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<Job>> fetchMine() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('my_deliveries'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(Job.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> claim(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'claim_delivery',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> abandon(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'abandon_delivery',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> arriveAtRestaurant(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'arrive_at_restaurant',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> confirmPickup({
    required String orderId,
    required String otp,
  }) async => _readCodeVerdict(
    await _guard<String?>(
      () => _db.rpc<String?>(
        'confirm_pickup',
        params: <String, dynamic>{'p_order_id': orderId, 'p_otp': otp},
      ),
    ),
    reissuedBy: 'the restaurant',
  );

  @override
  Future<void> arriveAtCustomer(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'arrive_at_customer',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> confirmDelivered({
    required String orderId,
    required String otp,
  }) async => _readCodeVerdict(
    await _guard<String?>(
      () => _db.rpc<String?>(
        'confirm_delivered',
        params: <String, dynamic>{'p_order_id': orderId, 'p_otp': otp},
      ),
    ),
    reissuedBy: 'the customer',
  );

  /// The second table read in this file, and allowed for the same reason as the
  /// first: 0025 gives a rider a select policy on *their own* partner row. A
  /// function around it would enforce nothing the policy does not.
  @override
  Future<bool> fetchOnline() async {
    final Map<String, dynamic>? row = await _guard<Map<String, dynamic>?>(
      () => _db.from('delivery_partners').select('is_online').maybeSingle(),
    );
    // A rider whose row we cannot see is not on shift. Defaulting the other way
    // would show an "Online" badge to somebody the board is refusing.
    return row?['is_online'] as bool? ?? false;
  }

  @override
  Future<void> setOnline(bool online) => _guard<void>(
    () => _db.rpc<void>(
      'set_rider_online',
      params: <String, dynamic>{'p_online': online},
    ),
  );

  /// The two code checks are the only calls in this app that report a failure by
  /// **returning** rather than raising, and the reason is in 0049: raising would
  /// roll back the attempt counter that makes the five-guess cap a cap. So the
  /// verdict is turned back into an exception here — in one place, so no screen
  /// can forget to look at it and treat a refusal as a handover.
  void _readCodeVerdict(String? verdict, {required String reissuedBy}) =>
      switch (verdict) {
        'ok' => null,
        'wrong_code' => throw JobFailure(
          "That code doesn't match. Ask $reissuedBy to read it again.",
        ),
        'locked' => throw JobFailure(
          'Too many wrong codes. Ask $reissuedBy for a new one.',
        ),
        _ => throw const JobFailure(),
      };

  @override
  Future<List<EarningsDay>> fetchEarnings({
    required DateTime from,
    required DateTime to,
  }) async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>(
        'rider_earnings',
        params: <String, dynamic>{
          // Dates, not timestamps. The function takes `date` and compares
          // against the IST day a job was delivered on; sending an instant
          // would make the boundary depend on the phone's clock.
          'p_from': _asDate(from),
          'p_to': _asDate(to),
        },
      ),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(EarningsDay.fromJson)
        .toList(growable: false);
  }

  /// The one table read in this file, and the exception is deliberate.
  ///
  /// Everything else here is an RPC because migration 0025 gave riders no policy
  /// on `orders` at all — there is no table for those calls to read. `rider_payouts`
  /// is different: it is the rider's own row, it has a select policy scoped by
  /// `delivery_partner_email()` (0045), and wrapping that in a function would add
  /// a layer that enforces nothing the policy does not already enforce. Exactly
  /// what the vendor app does with `settlements`.
  @override
  Future<List<Payout>> fetchPayouts() async {
    final List<Map<String, dynamic>> rows =
        await _guard<List<Map<String, dynamic>>>(
          () => _db
              .from('rider_payouts')
              .select()
              // No `.eq('partner_email', …)`. The policy is the filter, and a
              // client-side one would only be a second place to get it wrong.
              .order('period_end', ascending: false),
        );
    return rows.map(Payout.fromJson).toList(growable: false);
  }

  static String _asDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 0025 raises every refusal as `P0001` with a sentence already written for a
  /// human — "Another partner just took that one." Passing it straight through
  /// beats inventing a vaguer one here.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw JobFailure(e.message);
      throw const JobFailure();
    }
  }
}
