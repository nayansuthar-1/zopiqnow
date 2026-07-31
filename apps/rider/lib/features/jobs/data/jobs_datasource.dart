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

  /// Jobs the dispatcher is asking *this* rider to take, right now (0056).
  Future<List<DeliveryOffer>> fetchOffers();

  /// A ping every time this rider's offers change — one row appearing is the
  /// event the sheet opens on. Carries no data of its own on purpose: the
  /// socket says "something moved", [fetchOffers] says what, and there is then
  /// one shape of an offer in the app rather than two that can disagree.
  Stream<void> watchOfferChanges(String partnerEmail);

  /// Yes. Creates the delivery, through the same `claim_delivery` race the board
  /// has always gone through.
  Future<void> acceptOffer(String orderId);

  /// No. The order moves to the next partner immediately, not when the
  /// countdown runs out.
  Future<void> declineOffer(String orderId);

  /// Where this rider is. Ignored by the database unless they are carrying
  /// something (0057).
  Future<void> recordLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speedKmh,
  });

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

  /// How much of the platform's cash this rider is carrying, and the ceiling
  /// (0076). An RPC and not a table read, unlike the payouts below: the ledger
  /// has RLS on and no policy at all, because a rider needs the total and has no
  /// use for the rows — and the cap lives in a one-row policy table that nobody
  /// outside the database reads.
  Future<CashInHand> fetchCashInHand();

  /// The sentences this rider may send, in the order to show them (0061).
  ///
  /// The role is not passed: `order_message_menu` derives it from the caller, so
  /// a rider asking for the list gets the rider's half of it and could not ask
  /// for the customer's.
  Future<List<CannedMessage>> fetchMessageMenu();

  /// The thread on a job, now and as either side adds to it.
  ///
  /// The one `.stream()` in this file, and the one place a rider reads a table
  /// rather than calling a function — `order_messages` has a policy scoped to
  /// the jobs this rider holds, which is the same guarantee an RPC would give
  /// and the only shape a subscription can take.
  Stream<List<JobMessage>> watchMessages(String orderId);

  /// Says one of [fetchMessageMenu]'s lines. Throws [JobFailure] with the
  /// database's own sentence when it refuses.
  Future<void> sendMessage({required String orderId, required String code});

  /// Marks the customer's lines seen. Never throws.
  Future<void> markMessagesRead(String orderId);
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
  Future<List<DeliveryOffer>> fetchOffers() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('my_offers'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(DeliveryOffer.fromJson)
        .toList(growable: false);
  }

  /// The third table read in this file, and the last.
  ///
  /// `delivery_offers` has a select policy scoped to the rider's own email
  /// (0056) — the same shape as `rider_payouts` below, and allowed for the same
  /// reason. It is used only as a doorbell: the rows it delivers are thrown
  /// away and [fetchOffers] is called for the answer, because the RPC joins in
  /// the restaurant, the distance and the fee that a raw offer row does not
  /// carry.
  @override
  Stream<void> watchOfferChanges(String partnerEmail) {
    return _db
        .from('delivery_offers')
        .stream(primaryKey: const <String>['id'])
        // Not the security boundary — the policy is. This is so the socket
        // carries one rider's offers rather than being asked to.
        .eq('partner_email', partnerEmail)
        .map((List<Map<String, dynamic>> _) {});
  }

  @override
  Future<void> acceptOffer(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'accept_offer',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> declineOffer(String orderId) => _guard<void>(
    () => _db.rpc<void>(
      'decline_offer',
      params: <String, dynamic>{'p_order_id': orderId},
    ),
  );

  @override
  Future<void> recordLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speedKmh,
  }) => _guard<void>(
    () => _db.rpc<void>(
      'record_rider_location',
      params: <String, dynamic>{
        'p_lat': lat,
        'p_lng': lng,
        'p_heading': heading,
        'p_speed': speedKmh,
      },
    ),
  );

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

  /// `my_cash_in_hand` returns a table, so PostgREST sends a one-row array. An
  /// empty one is impossible — the function raises for a non-rider rather than
  /// returning nothing — but a rider on a bike is not the person to show a cast
  /// error to, so the empty case reads as nothing owed.
  @override
  Future<CashInHand> fetchCashInHand() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('my_cash_in_hand'),
    );
    if (rows.isEmpty) return const CashInHand(outstanding: 0, cap: 0);
    return CashInHand.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<List<CannedMessage>> fetchMessageMenu() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('order_message_menu'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(CannedMessage.fromJson)
        .toList(growable: false);
  }

  /// The second table read in this file, and for the same reason as
  /// [fetchPayouts]: `order_messages` has a select policy scoped to the jobs
  /// this rider actually holds (0061), and a function wrapping it would enforce
  /// nothing the policy does not. Writes are still an RPC — the policy set
  /// grants `select` and nothing else, so a message can only be said through
  /// `send_order_message`, which is what makes "canned" mean anything.
  @override
  Stream<List<JobMessage>> watchMessages(String orderId) {
    return _db
        .from('order_messages')
        .stream(primaryKey: const <String>['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(JobMessage.fromJson).toList(growable: false),
        );
  }

  @override
  Future<void> sendMessage({
    required String orderId,
    required String code,
  }) async {
    // `int`, not `void`: the function returns the new message's id, and asking
    // the client to decode a bigint as void is how a successful send comes back
    // as a type error.
    await _guard<int>(
      () => _db.rpc<int>(
        'send_order_message',
        params: <String, dynamic>{'p_order_id': orderId, 'p_code': code},
      ),
    );
  }

  @override
  Future<void> markMessagesRead(String orderId) async {
    try {
      await _db.rpc<void>(
        'mark_order_messages_read',
        params: <String, dynamic>{'p_order_id': orderId},
      );
    } on PostgrestException {
      // A read receipt nobody got. There is nothing a rider on a bike could do
      // about it, and nothing worth a snackbar.
    }
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
