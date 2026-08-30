import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/data/jobs_datasource.dart';
import 'package:zopiq_rider/features/jobs/data/location_reporter.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<JobsDataSource> jobsDataSourceProvider =
    Provider<JobsDataSource>((Ref ref) => const JobsSupabaseDataSource());

/// The board — now the *leftovers*, not the front door (0056).
///
/// An order is offered to one rider at a time and only reaches this list once
/// the fleet has declined or ignored it. So it is short, it is often empty, and
/// nothing about it is urgent — which is exactly why the twenty-second timer
/// that used to sit beside it is gone.
///
/// A one-shot read refreshed by pull-to-refresh, after every write, and whenever
/// this rider's offers change. A live subscription is still not possible:
/// `available_deliveries` is a function, Realtime rides table policies, and
/// riders have no policy on `orders` at all (0025). But it no longer needs to
/// be — [offerSignalProvider] is the socket that says something moved, and the
/// board is refreshed off the back of it.
final FutureProvider<List<JobOffer>> boardProvider =
    FutureProvider<List<JobOffer>>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) return Future<List<JobOffer>>.value(const <JobOffer>[]);
      return ref.watch(jobsDataSourceProvider).fetchBoard();
    });

/// The doorbell. Fires whenever a row in this rider's `delivery_offers` appears,
/// changes or expires.
///
/// The stream carries nothing — see the data source. Two things watch it: the
/// offers themselves, and the board, because an order being offered to somebody
/// leaves the board and an order nobody took rejoins it.
final StreamProvider<void> offerSignalProvider = StreamProvider<void>((Ref ref) {
  final Rider? rider = ref.watch(riderProvider);
  if (rider == null) return const Stream<void>.empty();
  return ref.watch(jobsDataSourceProvider).watchOfferChanges(rider.email);
});

/// What this rider is being asked to take, right now.
///
/// Refetched on every ping from [offerSignalProvider], which is what makes the
/// sheet appear within a socket round trip of the dispatcher choosing this
/// rider — no polling, and no waiting for FCM to deliver the push that wakes a
/// *dark* screen.
///
/// Rows that have already expired are dropped here rather than trusted from the
/// server, because a sheet is a screen a phone can hold open through a tunnel:
/// `my_offers` filters on the database's clock at the moment it is asked, and
/// this filters again at the moment it is drawn — against the database's clock
/// as well, corrected for this phone's (0151). Filtering on the raw device clock
/// is what made a phone one minute fast discard every offer it was ever sent.
final FutureProvider<List<DeliveryOffer>> offersProvider =
    FutureProvider<List<DeliveryOffer>>((Ref ref) async {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) return const <DeliveryOffer>[];

      // Watched, not read: this is the whole refresh mechanism.
      ref.watch(offerSignalProvider);

      // An offer landing means the board changed too — the order it names has
      // just left it.
      ref.invalidate(boardProvider);

      final List<DeliveryOffer> offers = await ref
          .watch(jobsDataSourceProvider)
          .fetchOffers();
      return offers
          .where((DeliveryOffer o) => !o.isExpired)
          .toList(growable: false);
    });

/// The one offer the sheet draws, or null.
///
/// The soonest to expire when there is somehow more than one — which the
/// database prevents per *order* but not per rider, since 0056 refuses to offer
/// a second job to a rider already deciding about one. Belt and braces: the
/// rider sees one countdown, always.
final Provider<DeliveryOffer?> currentOfferProvider = Provider<DeliveryOffer?>((
  Ref ref,
) {
  final List<DeliveryOffer> offers = ref
      .watch(offersProvider)
      .maybeWhen(
        data: (List<DeliveryOffer> o) => o,
        orElse: () => const <DeliveryOffer>[],
      );
  return offers.isEmpty ? null : offers.first;
});

/// Whether this rider is on shift.
///
/// `is_active` is ops saying you work here; this is the rider saying they are
/// working *now* (0049). Kept out of [Rider] deliberately: that object is
/// resolved once at sign-in and never changes, and a shift changes several times
/// a day — folding a mutable fact into an immutable one is how a screen ends up
/// showing a state the database left behind an hour ago.
final FutureProvider<bool> riderOnlineProvider = FutureProvider<bool>((Ref ref) {
  final Rider? rider = ref.watch(riderProvider);
  if (rider == null) return Future<bool>.value(false);
  return ref.watch(jobsDataSourceProvider).fetchOnline();
});

/// This rider's jobs.
final FutureProvider<List<Job>> myJobsProvider = FutureProvider<List<Job>>((
  Ref ref,
) {
  final Rider? rider = ref.watch(riderProvider);
  if (rider == null) return Future<List<Job>>.value(const <Job>[]);
  return ref.watch(jobsDataSourceProvider).fetchMine();
});

/// Everything the rider is currently carrying or collecting — their run.
///
/// 8b-2 showed one job at a time and said why: a screen with one bag and one
/// address is the difference between an app somebody can use while holding a
/// helmet and one they cannot. That was right for one job and wrong as a limit.
/// The database never enforced it (8b-4 left concurrent claims uncapped on
/// purpose — "batching is the job"), so the app was the only thing stopping a
/// rider doing what riders actually do: take three orders from one street.
///
/// **Ordered by what can be acted on now, and deliberately not by route.** The
/// app knows two dots on a map and nothing about the roads between them; a list
/// that looked like a planned route would be a claim it cannot support. So:
/// packed and waiting first, then what is already on the bike, then what is
/// still cooking — and within each, oldest first.
final Provider<List<Job>> activeJobsProvider = Provider<List<Job>>((Ref ref) {
  final List<Job> live = ref
      .watch(myJobsProvider)
      .maybeWhen(
        data: (List<Job> jobs) =>
            jobs.where((Job j) => j.state.isLive).toList(),
        orElse: () => <Job>[],
      );

  int rank(Job j) {
    if (!j.isCarrying && j.isReadyToCollect) return 0;
    if (j.isCarrying) return 1;
    return 2;
  }

  live.sort((Job a, Job b) {
    final int byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.claimedAt.compareTo(b.claimedAt);
  });
  return List<Job>.unmodifiable(live);
});

/// The thing that sends the rider's position while they are carrying (0057).
///
/// A single long-lived object rather than one per screen: the stream it holds is
/// a GPS subscription, and two of those is two radios' worth of battery for one
/// dot on a map. Disposed with the container, which for this app means sign-out.
final Provider<RiderLocationReporter> locationReporterProvider =
    Provider<RiderLocationReporter>((Ref ref) {
      final RiderLocationReporter reporter = RiderLocationReporter(
        ref.watch(jobsDataSourceProvider),
      );
      ref.onDispose(reporter.stop);
      return reporter;
    });

/// Whether the rider has a bag on the bike right now.
///
/// *Carrying*, not *has a live job*: a rider riding to a kitchen is not on
/// anybody's tracking screen, and following them there would be collecting a
/// position for which there is no reader.
///
/// Its own provider because two things key off it — the location stream below,
/// and the shell's battery-optimisation prompt, which has to fire on the same
/// edge the tracking does or it asks at a moment that means nothing.
final Provider<bool> carryingProvider = Provider<bool>(
  (Ref ref) => ref.watch(activeJobsProvider).any((Job j) => j.isCarrying),
);

/// Turns the reporter on and off from the rider's own jobs.
///
/// Watched by the shell, so it is alive for as long as the app is.
final Provider<void> locationReportingProvider = Provider<void>((Ref ref) {
  // Deliberately not awaited. This provider's job is to notice the change and
  // pass it on; the reporter is idempotent and handles its own failures.
  unawaited(
    ref
        .watch(locationReporterProvider)
        .setCarrying(ref.watch(carryingProvider)),
  );
});

/// The last 30 days of earnings, by day.
///
/// A fixed window rather than a range the rider picks. Thirty days answers both
/// questions somebody actually opens this screen with — "what did I make today"
/// and "what did I make this week" — and a date picker for the third question
/// is a control nobody asked for.
final FutureProvider<List<EarningsDay>> earningsProvider =
    FutureProvider<List<EarningsDay>>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) {
        return Future<List<EarningsDay>>.value(const <EarningsDay>[]);
      }
      final DateTime today = DateTime.now();
      return ref
          .watch(jobsDataSourceProvider)
          .fetchEarnings(
            from: today.subtract(const Duration(days: 29)),
            to: today,
          );
    });

/// Today and the last seven days, totalled off [earningsProvider].
///
/// Derived rather than fetched: the daily rows are already here, and a second
/// round trip to re-sum numbers the app is holding would be a slower way to get
/// the same answer.
@immutable
class EarningsSummary {
  const EarningsSummary({
    required this.todayJobs,
    required this.todayPay,
    required this.weekJobs,
    required this.weekPay,
  });

  final int todayJobs;
  final int todayPay;
  final int weekJobs;
  final int weekPay;
}

final Provider<EarningsSummary> earningsSummaryProvider =
    Provider<EarningsSummary>((Ref ref) {
      final List<EarningsDay> days = ref
          .watch(earningsProvider)
          .maybeWhen(
            data: (List<EarningsDay> d) => d,
            orElse: () => const <EarningsDay>[],
          );

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      // Seven days *including* today, which is what "this week" means to
      // somebody counting shifts — not Monday-to-now, which reads as a bad week
      // every Monday morning.
      final DateTime weekStart = today.subtract(const Duration(days: 6));

      int todayJobs = 0, todayPay = 0, weekJobs = 0, weekPay = 0;
      for (final EarningsDay d in days) {
        final DateTime day = DateTime(d.day.year, d.day.month, d.day.day);
        if (!day.isBefore(weekStart)) {
          weekJobs += d.jobs;
          weekPay += d.earnings;
        }
        if (day == today) {
          todayJobs = d.jobs;
          todayPay = d.earnings;
        }
      }
      return EarningsSummary(
        todayJobs: todayJobs,
        todayPay: todayPay,
        weekJobs: weekJobs,
        weekPay: weekPay,
      );
    });

/// The weekly pay batches. Separate from [earningsProvider] because they answer
/// different questions: earnings is "what have I made", payouts is "where is it".
final FutureProvider<List<Payout>> payoutsProvider =
    FutureProvider<List<Payout>>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) return Future<List<Payout>>.value(const <Payout>[]);
      return ref.watch(jobsDataSourceProvider).fetchPayouts();
    });

/// The platform's cash in this rider's pocket (0076).
///
/// Refreshed by every write, because the one that matters — `confirmDelivered`
/// on a cash order — is the write that moves it, and a chip still reading ₹0
/// after the rider has just been handed ₹500 is the app disagreeing with the
/// notes in their hand.
final FutureProvider<CashInHand> cashInHandProvider =
    FutureProvider<CashInHand>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) {
        return Future<CashInHand>.value(
          const CashInHand(outstanding: 0, cap: 0),
        );
      }
      return ref.watch(jobsDataSourceProvider).fetchCashInHand();
    });

/// Finished jobs, newest first — the "what have I done" list under the totals.
final Provider<List<Job>> deliveredJobsProvider = Provider<List<Job>>((Ref ref) {
  return ref
      .watch(myJobsProvider)
      .maybeWhen(
        data: (List<Job> jobs) => jobs
            .where((Job j) => j.state == JobState.delivered)
            .toList(growable: false),
        orElse: () => const <Job>[],
      );
});

/// Every write the rider makes. Each returns null on success or a sentence to
/// show — the shape both other apps use.
///
/// All of them refresh both lists, because every one moves a job across the
/// boundary between them: claiming takes it off the board and onto the rider,
/// abandoning puts it back, delivering ends it — and delivering also moves the
/// earnings total, so that goes too.
/// The thread on one job, live (0061).
///
/// Streamed rather than fetched, unlike every other read in this app: a customer
/// answering "which gate?" while the rider is sitting outside their building is
/// the entire reason the feature exists. Errors are swallowed to nothing — a
/// thread that went red because a socket hiccuped would look, to a rider at a
/// kerb, like the customer had hung up.
final AutoDisposeStreamProviderFamily<List<JobMessage>, String>
jobMessagesProvider =
    StreamProvider.autoDispose.family<List<JobMessage>, String>((
      Ref ref,
      String orderId,
    ) {
      return ref
          .watch(jobsDataSourceProvider)
          .watchMessages(orderId)
          .handleError((Object _) {});
    });

/// The sentences this rider may send. A constant on the server, so one round
/// trip per time the sheet is opened rather than one per message.
final AutoDisposeFutureProvider<List<CannedMessage>> messageMenuProvider =
    FutureProvider.autoDispose<List<CannedMessage>>(
      (Ref ref) => ref.watch(jobsDataSourceProvider).fetchMessageMenu(),
    );

class JobsController extends Notifier<void> {
  @override
  void build() {}

  JobsDataSource get _ds => ref.read(jobsDataSourceProvider);

  /// Yes — from the offer sheet or from a card on the board; there is one door
  /// for both since 0148.
  ///
  /// Returns null when the job is this rider's, and a sentence to show when it
  /// is not. The database's own refusals are passed straight through, because
  /// they are already written for a human: "You are offline. Go online to take
  /// deliveries.", "Another partner was closer to the restaurant."
  ///
  /// **The wait.** An accept on a job only this rider can see comes straight
  /// back. An accept on one two or three riders can see opens a two-second
  /// window so the nearest of them wins rather than the fastest — and then this
  /// method sleeps out the window and asks for the verdict. [onContested] fires
  /// on that branch and only that branch, so a button can say "Confirming…"
  /// instead of spinning silently at somebody standing over a bike.
  ///
  /// Waiting on the device rather than in the database is deliberate: holding a
  /// connection open with `pg_sleep` for every accept on a 60-connection
  /// instance is how a busy evening becomes an outage. The verdict is settled by
  /// whichever contestant asks first, and every other one is told the same
  /// answer — so a rider whose phone dies mid-wait changes nothing, and the
  /// dispatch tick settles it for them.
  Future<String?> take(String orderId, {void Function()? onContested}) async {
    try {
      TakeOutcome outcome = await _ds.takeDelivery(orderId);

      if (outcome.isPending) {
        onContested?.call();
        await Future<void>.delayed(outcome.waitFrom(DateTime.now()));
        outcome = await _ds.resolveContest(orderId);
      }

      // Refreshed whichever way it went. A loss moves the board just as much as
      // a win does — the order now has somebody on it and leaves every list.
      _refresh();

      if (outcome.isWon) return null;
      return outcome.message ?? 'Another partner got that one.';
    } on JobFailure catch (e) {
      _refresh();
      return e.message;
    } on Object {
      _refresh();
      return 'We couldn\'t take that job.';
    }
  }

  /// No. Never reports a failure to the rider, and that is deliberate: the
  /// answer to "we could not record your decline" is the same as the answer to
  /// a successful one — the sheet closes and the order goes to somebody else,
  /// either now or when the countdown runs out. An error toast here would be a
  /// rider being told off for saying no.
  Future<String?> declineOffer(String orderId) async {
    await _write(() => _ds.declineOffer(orderId), '');
    return null;
  }

  Future<String?> abandon(String orderId) =>
      _write(() => _ds.abandon(orderId), 'We couldn\'t drop that job.');

  Future<String?> arriveAtRestaurant(String orderId) => _write(
    () => _ds.arriveAtRestaurant(orderId),
    'We couldn\'t tell the restaurant you\'re here.',
  );

  Future<String?> confirmPickup({
    required String orderId,
    required String otp,
  }) => _write(
    () => _ds.confirmPickup(orderId: orderId, otp: otp),
    'We couldn\'t confirm the pickup.',
  );

  Future<String?> arriveAtCustomer(String orderId) => _write(
    () => _ds.arriveAtCustomer(orderId),
    'We couldn\'t tell the customer you\'re here.',
  );

  Future<String?> confirmDelivered({
    required String orderId,
    required String otp,
    String? photoUrl,
  }) => _write(
    () => _ds.confirmDelivered(
      orderId: orderId,
      otp: otp,
      photoUrl: photoUrl,
    ),
    'We couldn\'t mark that delivered.',
  );

  /// Going off shift. Not optimistic, unlike most toggles in these apps: the
  /// database refuses this while the rider is carrying anything, and a switch
  /// that flips to "Offline" and then snaps back has already told the rider they
  /// were done for the day.
  Future<String?> setOnline(bool online) => _write(
    () => _ds.setOnline(online),
    online
        ? 'We couldn\'t start your shift.'
        : 'We couldn\'t end your shift.',
  );

  /// Says one canned line to the customer.
  ///
  /// Deliberately **not** routed through [_write]: sending a message changes no
  /// job state, and invalidating the board, the offers and the earnings on every
  /// chip tap would be six requests to say "on my way". The thread refreshes
  /// itself over its own socket.
  Future<String?> sendMessage({
    required String orderId,
    required String code,
  }) async {
    try {
      await _ds.sendMessage(orderId: orderId, code: code);
      return null;
    } on JobFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t send that.';
    }
  }

  /// Marks the customer's lines seen. Never reports anything — see
  /// [JobsDataSource.markMessagesRead].
  Future<void> markMessagesRead(String orderId) =>
      _ds.markMessagesRead(orderId);

  Future<String?> _write(Future<void> Function() call, String fallback) async {
    try {
      await call();
      _refresh();
      return null;
    } on JobFailure catch (e) {
      return e.message;
    } on Object {
      return fallback;
    }
  }

  /// Every list a job write can move. Its own method since 0148, because
  /// [take] needs the same refresh and does not fit [_write]'s
  /// success-is-void shape — a contest can come back "you lost", which is not a
  /// failure but still moves every one of these.
  void _refresh() {
    ref
      ..invalidate(boardProvider)
      ..invalidate(myJobsProvider)
      // Accepting retires an offer, declining retires an offer, and claiming
      // from the board can retire somebody else's. One line covers all three.
      ..invalidate(offersProvider)
      // The board is empty while offline and full while on, so a shift change
      // is a board change — and every job write can be the one that frees a
      // rider to end their shift.
      ..invalidate(riderOnlineProvider)
      // Only `confirmDelivered` can actually move this, but invalidating on
      // every write costs one request the rider never waits on and removes
      // the failure mode where a total is stale because the list that feeds
      // it was refreshed and it was not.
      ..invalidate(earningsProvider)
      // Same reasoning, and one more: a claim that was refused for being over
      // the cash ceiling is a rider who should immediately see the number that
      // refused them.
      ..invalidate(cashInHandProvider);
  }
}

final NotifierProvider<JobsController, void> jobsControllerProvider =
    NotifierProvider<JobsController, void>(JobsController.new);
