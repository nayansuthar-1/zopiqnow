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

  /// Collect the bag, proving it with the code the restaurant reads out.
  Future<void> confirmPickup({required String orderId, required String otp});

  Future<void> confirmDelivered(String orderId);
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
  Future<void> confirmPickup({
    required String orderId,
    required String otp,
  }) => _guard<void>(
    () => _db.rpc<void>(
      'confirm_pickup',
      params: <String, dynamic>{'p_order_id': orderId, 'p_otp': otp},
    ),
  );

  @override
  Future<void> confirmDelivered(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'confirm_delivered',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

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
