import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

/// The board re-asks on a timer, because nothing can tell it a job appeared:
/// `available_deliveries` is a function, Realtime rides table policies, and
/// riders have no policy on `orders` (0025).
///
/// Unlike every other test file here, this one *wants* the timer — so it runs
/// inside `fakeAsync` via `tester.pump(duration)`, which advances the test
/// clock rather than waiting in real time.

Widget _app({required FakeJobsDataSource jobs, Duration? poll}) => ProviderScope(
  overrides: <Override>[
    riderAuthDataSourceProvider.overrideWithValue(
      FakeRiderAuthDataSource(signedInAs: testRider),
    ),
    jobsDataSourceProvider.overrideWithValue(jobs),
    boardPollIntervalProvider.overrideWithValue(poll),
  ],
  child: const RiderApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a job that appears while the rider waits shows up on its own', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource();
    await tester.pumpWidget(
      _app(jobs: jobs, poll: const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing waiting'), findsOneWidget);

    // A kitchen finishes cooking. Nothing tells the app.
    jobs.arrive(offer());

    // Before the tick, the rider is still looking at an empty board — this is
    // the state the whole slice exists to shorten, so it is worth asserting.
    await tester.pump(const Duration(seconds: 19));
    expect(find.text('Paradise Biryani'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Paradise Biryani'), findsOneWidget);

    // Leave nothing pending: the board is still mounted and still ticking.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a refresh does not blink the board away to a spinner', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    );
    await tester.pumpWidget(
      _app(jobs: jobs, poll: const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paradise Biryani'), findsOneWidget);

    // From here the next fetch takes a visible moment, as it does on a phone.
    jobs.fetchDelay = const Duration(seconds: 3);
    await tester.pump(const Duration(seconds: 21));

    // Mid-refresh. The rider is reading this screen and may be about to tap a
    // job on it — replacing it with a progress indicator every twenty seconds
    // would be worse than never refreshing at all.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Paradise Biryani'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Paradise Biryani'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('taking a job stops the polling', (WidgetTester tester) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    );
    await tester.pumpWidget(
      _app(jobs: jobs, poll: const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take this job'));
    await tester.pumpAndSettle();
    expect(find.text('Your job'), findsOneWidget);

    // The board is gone, so its timer is gone with it. If it were not, this
    // pump would leave a pending timer and fail the test — which is the
    // assertion, and why there is no expect() after it.
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('with polling off, an arrived job waits for a pull', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource();
    await tester.pumpWidget(_app(jobs: jobs, poll: null));
    await tester.pumpAndSettle();

    jobs.arrive(offer());
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();

    expect(find.text('Paradise Biryani'), findsNothing);
  });
}
