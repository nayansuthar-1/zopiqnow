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

/// Every write the rider makes. Each returns null on success or a sentence to
/// show — the shape both other apps use.
///
/// All five refresh *both* lists, because every one of them moves a job across
/// the boundary between them: claiming takes it off the board and onto the
/// rider, abandoning puts it back, delivering ends it.
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
        ..invalidate(myJobsProvider);
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
