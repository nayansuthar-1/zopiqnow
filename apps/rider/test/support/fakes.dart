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

  @override
  Future<void> sendEmailOtp(String email) async => lastCodeSentTo = email;

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
  }) : _board = List<JobOffer>.of(board),
       _mine = List<Job>.of(mine);

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

  @override
  Future<List<JobOffer>> fetchBoard() async => List<JobOffer>.unmodifiable(_board);

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
        deliverTo: offer.deliverTo,
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
        deliveredAt: null,
      ),
    ];
  }

  @override
  Future<void> abandon(String orderId) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    if (job.state != JobState.claimed) {
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
  Future<void> confirmPickup({
    required String orderId,
    required String otp,
  }) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
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
  Future<void> confirmDelivered(String orderId) async {
    final Job job = _mine.firstWhere((Job j) => j.orderId == orderId);
    _replace(job, state: JobState.delivered, orderStatus: 'delivered');
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

  void _replace(Job job, {required JobState state, required String orderStatus}) {
    _mine = _mine
        .map(
          (Job j) => j.orderId == job.orderId
              ? Job(
                  orderId: j.orderId,
                  state: state,
                  orderStatus: orderStatus,
                  restaurantName: j.restaurantName,
                  deliverTo: j.deliverTo,
                  customerPhone: j.customerPhone,
                  total: j.total,
                  isCash: j.isCash,
                  distanceKm: j.distanceKm,
                  payBase: j.payBase,
                  payPerKm: j.payPerKm,
                  riderPay: j.riderPay,
                  claimedAt: j.claimedAt,
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
}) => Job(
  orderId: orderId,
  state: state,
  orderStatus: orderStatus,
  restaurantName: 'Paradise Biryani',
  deliverTo: 'Banjara Hills, Hyderabad',
  customerPhone: '+919876543210',
  total: 720,
  isCash: isCash,
  distanceKm: distanceKm,
  payBase: payBase,
  payPerKm: payPerKm,
  riderPay: riderPay,
  claimedAt: DateTime.now().subtract(const Duration(minutes: 3)),
  // A delivered job without a delivery time is not a state the database can be
  // in, so the helper fills it rather than letting a test construct one.
  deliveredAt:
      deliveredAt ??
      (state == JobState.delivered ? DateTime.now() : null),
);
