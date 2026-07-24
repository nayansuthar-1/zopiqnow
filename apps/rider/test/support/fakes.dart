import 'package:zopiq_rider/core/launcher.dart';
import 'package:zopiq_rider/features/auth/data/rider_auth_datasource.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/jobs/data/jobs_datasource.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

const Rider testRider = Rider(
  email: 'nayan@siteonlab.com',
  name: 'Nayan',
  phone: '+919000000001',
);

class FakeRiderAuthDataSource implements RiderAuthDataSource {
  FakeRiderAuthDataSource({this.signedInAs, this.isPartner = true});

  /// The session in the Keystore, if any.
  final Rider? signedInAs;

  /// Whether the address that verifies an OTP turns out to ride for Zopiqnow.
  final bool isPartner;

  String? lastCodeSentTo;

  /// Set to make the send fail the way the auth service does — with a sentence
  /// of its own that the screen is supposed to pass through, not replace.
  String? sendFailsWith;

  /// Set to make the send fail the way a dead network does: not an auth error
  /// at all, just an exception.
  bool sendThrowsNetworkError = false;

  @override
  Future<void> sendEmailOtp(String email) async {
    if (sendThrowsNetworkError) throw Exception('SocketException');
    if (sendFailsWith != null) throw RiderAuthFailure(sendFailsWith!);
    lastCodeSentTo = email;
  }

  @override
  Future<Rider?> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    if (code != '123456') throw const RiderAuthFailure();
    return isPartner ? testRider : null;
  }

  @override
  Future<Rider?> restoreSession() async => signedInAs;

  @override
  Future<void> signOut() async {}
}

/// The board and the rider's jobs, in memory, behaving the way 0025 does: a
/// claim moves a row from one list to the other, and the refusals are the
/// database's own sentences.
class FakeJobsDataSource implements JobsDataSource {
  FakeJobsDataSource({
    List<JobOffer> board = const <JobOffer>[],
    List<Job> mine = const <Job>[],
    this.payouts = const <Payout>[],
  }) : _board = List<JobOffer>.of(board),
       _mine = List<Job>.of(mine);

  /// Pay batches, which nothing the rider does can create — the weekly rollup
  /// makes them and an admin marks them paid (0045). So they are fixture, not
  /// state this fake evolves.
  final List<Payout> payouts;

  /// The two codes the fake will accept, and the shift it starts in. Riders
  /// default to on shift, exactly as `is_online` defaults in 0049.
  String deliveryOtp = '4321';
  bool online = true;

  List<JobOffer> _board;
  List<Job> _mine;

  /// Set to make the next claim lose the race, the way a second rider tapping
  /// the same job a half-second later does.
  bool claimLoses = false;

  /// Codes this fake will accept. Anything else is refused, like the real one.
  String otp = '5896';

  /// The rates a claim snapshots, standing in for `rider_pay_rates` (0043).
  /// [claimDistanceKm] set to null is the real case where the restaurant has no
  /// coordinates on file and only the base fee can be paid.
  int payBase = 25;
  double payPerKm = 5;
  double? claimDistanceKm = 4.2;

  List<Job> get mine => List<Job>.unmodifiable(_mine);

  /// A kitchen finishes cooking something nobody has claimed. Nothing tells the
  /// app — the next `fetchBoard` simply sees more than the last one did, which
  /// is exactly how a new job reaches a rider in production.
  void arrive(JobOffer o) => _board = <JobOffer>[..._board, o];

  /// How long a board fetch takes. Zero everywhere except the test that checks
  /// what is on screen *during* a refresh — with an instant fake there is no
  /// during.
  Duration fetchDelay = Duration.zero;

  @override
  Future<List<JobOffer>> fetchBoard() async {
    if (fetchDelay > Duration.zero) await Future<void>.delayed(fetchDelay);
    return List<JobOffer>.unmodifiable(_board);
  }

  @override
  Future<List<Job>> fetchMine() async => List<Job>.unmodifiable(_mine);

  @override
  Future<void> claim(String orderId) async {
    if (claimLoses) {
      throw const JobFailure('Another partner just took that one.');
    }
    final JobOffer offer = _board.firstWhere((JobOffer o) => o.orderId == orderId);
    _board = _board.where((JobOffer o) => o.orderId != orderId).toList();
    _mine = <Job>[
      ..._mine,
      Job(
        orderId: offer.orderId,
        state: JobState.claimed,
        orderStatus: offer.isReady ? 'ready_for_pickup' : 'preparing',
        restaurantName: offer.restaurantName,
        restaurantLat: 24.6061,
        restaurantLng: 72.3283,
        deliverTo: offer.deliverTo,
        deliverLat: 24.5881,
        deliverLng: 72.3163,
        customerPhone: '+919876543210',
        total: offer.total,
        isCash: offer.isCash,
        distanceKm: claimDistanceKm,
        payBase: payBase,
        payPerKm: payPerKm,
        // The same sum 0043 does, including the rule that matters: an
        // unmeasurable distance pays the base and nothing more.
        riderPay: payBase + ((claimDistanceKm ?? 0) * payPerKm).round(),
        claimedAt: DateTime.now(),
        arrivedAtRestaurantAt: null,
        arrivedAtCustomerAt: null,
        deliveredAt: null,
      ),
    ];
  }

  @override
  Future<void> abandon(String orderId) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (!job.state.isCollecting) {
      throw const JobFailure(
        'You can only drop a job you haven\'t picked up yet.',
      );
    }
    _mine = _mine.where((Job j) => j.orderId != orderId).toList();
    _board = <JobOffer>[
      ..._board,
      JobOffer(
        orderId: job.orderId,
        restaurantName: job.restaurantName,
        deliverTo: job.deliverTo,
        total: job.total,
        isCash: job.isCash,
        isReady: job.isReadyToCollect,
        placedAt: job.claimedAt,
      ),
    ];
  }

  @override
  Future<void> arriveAtRestaurant(String orderId) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (job.state != JobState.claimed) {
      throw const JobFailure(
        'You have no job waiting to be collected on that order.',
      );
    }
    _replace(job, state: JobState.arrivedAtRestaurant);
  }

  /// The arrival gate is 0049's, not the app's — so the fake refuses a pickup
  /// from `claimed` the same way Postgres does. A fake that let it through would
  /// let a screen that skips the step pass its own tests.
  @override
  Future<void> confirmPickup({
    required String orderId,
    required String otp,
  }) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (job.state != JobState.arrivedAtRestaurant) {
      throw const JobFailure(
        'Tap "I\'ve arrived" at the restaurant before collecting the order.',
      );
    }
    if (!job.isReadyToCollect) {
      throw const JobFailure('That order isn\'t packed yet.');
    }
    if (otp != this.otp) {
      throw const JobFailure(
        'That code doesn\'t match. Ask the restaurant to read it again.',
      );
    }
    _replace(job, state: JobState.pickedUp, orderStatus: 'out_for_delivery');
  }

  @override
  Future<void> arriveAtCustomer(String orderId) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (job.state != JobState.pickedUp) {
      throw const JobFailure('You aren\'t carrying that order.');
    }
    _replace(job, state: JobState.arrivedAtCustomer);
  }

  @override
  Future<void> confirmDelivered({
    required String orderId,
    required String otp,
  }) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (job.state != JobState.arrivedAtCustomer) {
      throw const JobFailure(
        'Tap "I\'ve arrived" at the customer before completing the delivery.',
      );
    }
    if (otp != deliveryOtp) {
      throw const JobFailure(
        'That code doesn\'t match. Ask the customer to read it again.',
      );
    }
    _replace(job, state: JobState.delivered, orderStatus: 'delivered');
  }

  @override
  Future<bool> fetchOnline() async => online;

  @override
  Future<void> setOnline(bool value) async {
    if (!value && _mine.any((Job j) => j.state.isLive)) {
      throw const JobFailure(
        'Finish or drop your live job(s) before going offline.',
      );
    }
    online = value;
  }

  /// Earnings, derived from the delivered rows exactly as `rider_earnings`
  /// derives them — delivered only, grouped by the day it was delivered.
  @override
  Future<List<EarningsDay>> fetchEarnings({
    required DateTime from,
    required DateTime to,
  }) async {
    final Map<DateTime, List<Job>> byDay = <DateTime, List<Job>>{};
    for (final Job j in _mine) {
      if (j.state != JobState.delivered || j.deliveredAt == null) continue;
      final DateTime d = DateTime(
        j.deliveredAt!.year,
        j.deliveredAt!.month,
        j.deliveredAt!.day,
      );
      if (d.isBefore(DateTime(from.year, from.month, from.day))) continue;
      if (d.isAfter(DateTime(to.year, to.month, to.day))) continue;
      byDay.putIfAbsent(d, () => <Job>[]).add(j);
    }
    return byDay.entries
        .map(
          (MapEntry<DateTime, List<Job>> e) => EarningsDay(
            day: e.key,
            jobs: e.value.length,
            earnings: e.value.fold(0, (int sum, Job j) => sum + j.riderPay),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Payout>> fetchPayouts() async => List<Payout>.unmodifiable(payouts);

  void _replace(Job job, {required JobState state, String? orderStatus}) {
    _mine = _mine
        .map(
          (Job j) => j.orderId == job.orderId
              ? Job(
                  orderId: j.orderId,
                  state: state,
                  orderStatus: orderStatus ?? j.orderStatus,
                  restaurantName: j.restaurantName,
                  restaurantLat: j.restaurantLat,
                  restaurantLng: j.restaurantLng,
                  deliverTo: j.deliverTo,
                  deliverLat: j.deliverLat,
                  deliverLng: j.deliverLng,
                  customerPhone: j.customerPhone,
                  total: j.total,
                  isCash: j.isCash,
                  distanceKm: j.distanceKm,
                  payBase: j.payBase,
                  payPerKm: j.payPerKm,
                  riderPay: j.riderPay,
                  claimedAt: j.claimedAt,
                  arrivedAtRestaurantAt: state == JobState.arrivedAtRestaurant
                      ? DateTime.now()
                      : j.arrivedAtRestaurantAt,
                  arrivedAtCustomerAt: state == JobState.arrivedAtCustomer
                      ? DateTime.now()
                      : j.arrivedAtCustomerAt,
                  deliveredAt: state == JobState.delivered
                      ? DateTime.now()
                      : j.deliveredAt,
                )
              : j,
        )
        .toList();
  }
}

JobOffer offer({
  String orderId = 'ZPQ-1042',
  String restaurantName = 'Paradise Biryani',
  String deliverTo = 'Banjara Hills, Hyderabad',
  int total = 720,
  bool isCash = true,
  bool isReady = true,
}) => JobOffer(
  orderId: orderId,
  restaurantName: restaurantName,
  deliverTo: deliverTo,
  total: total,
  isCash: isCash,
  isReady: isReady,
  placedAt: DateTime.now().subtract(const Duration(minutes: 8)),
);

Job job({
  String orderId = 'ZPQ-1042',
  JobState state = JobState.claimed,
  String orderStatus = 'ready_for_pickup',
  bool isCash = true,
  double? distanceKm = 4.2,
  int payBase = 25,
  double payPerKm = 5,
  int riderPay = 46,
  DateTime? deliveredAt,
  // Null is the real case for a kitchen with no map location on file (0042),
  // which is what the navigation fallback exists for.
  double? restaurantLat = 24.6061,
  double? restaurantLng = 72.3283,
  String customerPhone = '+919876543210',
}) => Job(
  orderId: orderId,
  state: state,
  orderStatus: orderStatus,
  restaurantName: 'Paradise Biryani',
  restaurantLat: restaurantLat,
  restaurantLng: restaurantLng,
  deliverTo: 'Banjara Hills, Hyderabad',
  deliverLat: 24.5881,
  deliverLng: 72.3163,
  customerPhone: customerPhone,
  total: 720,
  isCash: isCash,
  distanceKm: distanceKm,
  payBase: payBase,
  payPerKm: payPerKm,
  riderPay: riderPay,
  claimedAt: DateTime.now().subtract(const Duration(minutes: 3)),
  // Filled in from the state for the same reason `deliveredAt` is: a job that
  // says it is at the door with no arrival time is not a row 0049 can produce.
  arrivedAtRestaurantAt: state == JobState.claimed
      ? null
      : DateTime.now().subtract(const Duration(minutes: 2)),
  arrivedAtCustomerAt:
      state == JobState.arrivedAtCustomer || state == JobState.delivered
      ? DateTime.now().subtract(const Duration(minutes: 1))
      : null,
  // A delivered job without a delivery time is not a state the database can be
  // in, so the helper fills it rather than letting a test construct one.
  deliveredAt:
      deliveredAt ??
      (state == JobState.delivered ? DateTime.now() : null),
);

Payout payout({
  int id = 1,
  DateTime? periodStart,
  DateTime? periodEnd,
  int deliveryCount = 3,
  int amount = 132,
  bool isPaid = false,
  String? reference,
}) => Payout(
  id: id,
  periodStart: periodStart ?? DateTime(2026, 7, 13),
  periodEnd: periodEnd ?? DateTime(2026, 7, 19),
  deliveryCount: deliveryCount,
  amount: amount,
  isPaid: isPaid,
  // A paid batch always has a reference and a time — 0045 has a check
  // constraint saying so, and a fixture that can violate it teaches the test
  // suite a shape the database cannot produce.
  reference: reference ?? (isPaid ? 'UTR123456789' : null),
  paidAt: isPaid ? DateTime(2026, 7, 20, 9) : null,
);

/// Records what the app *would* have opened.
///
/// The app's responsibility ends at the URI it hands to the platform — whether
/// a given phone has a maps app installed is not a thing these tests can or
/// should assert. So this captures the string and reports success.
class FakeLauncher implements Launcher {
  final List<String> opened = <String>[];

  /// Set to make every hand-off fail, the way a phone with no maps app does.
  bool succeeds = true;

  @override
  Future<bool> navigate({
    double? lat,
    double? lng,
    required String label,
  }) async {
    opened.add(
      lat != null && lng != null
          ? 'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})'
          : 'geo:0,0?q=${Uri.encodeComponent(label)}',
    );
    return succeeds;
  }

  @override
  Future<bool> dial(String phone) async {
    opened.add('tel:${Uri.encodeComponent(phone)}');
    return succeeds;
  }
}
