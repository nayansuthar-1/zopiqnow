import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/data/jobs_datasource.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<JobsDataSource> jobsDataSourceProvider =
    Provider<JobsDataSource>((Ref ref) => const JobsSupabaseDataSource());

/// The board. A one-shot read refreshed by pull-to-refresh and after every
/// write — not a stream.
///
/// A live subscription would be the obvious thing and is deliberately not here:
/// `available_deliveries` is a function, and Realtime rides table policies, not
/// functions. Since riders have no policy on `orders` at all (0025), there is
/// nothing for a socket to deliver. Polling on demand is the honest shape of the
/// thing until a job-offer push lands in a later slice.
final FutureProvider<List<JobOffer>> boardProvider =
    FutureProvider<List<JobOffer>>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) return Future<List<JobOffer>>.value(const <JobOffer>[]);
      return ref.watch(jobsDataSourceProvider).fetchBoard();
    });

/// This rider's jobs.
final FutureProvider<List<Job>> myJobsProvider = FutureProvider<List<Job>>((
  Ref ref,
) {
  final Rider? rider = ref.watch(riderProvider);
  if (rider == null) return Future<List<Job>>.value(const <Job>[]);
  return ref.watch(jobsDataSourceProvider).fetchMine();
});

/// The one job the rider is actually on, if any.
///
/// One at a time, deliberately. Nothing in the database stops a rider claiming
/// five orders — and a later slice may well want stacked deliveries — but a
/// screen that shows one bag and one address is the difference between an app
/// somebody can use while holding a helmet and one they cannot.
final Provider<Job?> activeJobProvider = Provider<Job?>((Ref ref) {
  return ref
      .watch(myJobsProvider)
      .maybeWhen(
        data: (List<Job> jobs) =>
            jobs.where((Job j) => j.state.isLive).firstOrNull,
        orElse: () => null,
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
class JobsController extends Notifier<void> {
  @override
  void build() {}

  JobsDataSource get _ds => ref.read(jobsDataSourceProvider);

  Future<String?> claim(String orderId) =>
      _write(() => _ds.claim(orderId), 'We couldn\'t take that job.');

  Future<String?> abandon(String orderId) =>
      _write(() => _ds.abandon(orderId), 'We couldn\'t drop that job.');

  Future<String?> confirmPickup({
    required String orderId,
    required String otp,
  }) => _write(
    () => _ds.confirmPickup(orderId: orderId, otp: otp),
    'We couldn\'t confirm the pickup.',
  );

  Future<String?> confirmDelivered(String orderId) => _write(
    () => _ds.confirmDelivered(orderId),
    'We couldn\'t mark that delivered.',
  );

  Future<String?> _write(Future<void> Function() call, String fallback) async {
    try {
      await call();
      ref
        ..invalidate(boardProvider)
        ..invalidate(myJobsProvider)
        // Only `confirmDelivered` can actually move this, but invalidating on
        // every write costs one request the rider never waits on and removes
        // the failure mode where a total is stale because the list that feeds
        // it was refreshed and it was not.
        ..invalidate(earningsProvider);
      return null;
    } on JobFailure catch (e) {
      return e.message;
    } on Object {
      return fallback;
    }
  }
}

final NotifierProvider<JobsController, void> jobsControllerProvider =
    NotifierProvider<JobsController, void>(JobsController.new);
