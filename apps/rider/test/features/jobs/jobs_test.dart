import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

Widget _app({
  Rider? signedInAs = testRider,
  required FakeJobsDataSource jobs,
}) => ProviderScope(
  overrides: <Override>[
    riderAuthDataSourceProvider.overrideWithValue(
      FakeRiderAuthDataSource(signedInAs: signedInAs),
    ),
    jobsDataSourceProvider.overrideWithValue(jobs),
    // No board polling under test. A live `Timer.periodic` outlives the widget
    // tree and fails the test with a pending-timer error; the auto-refresh has
    // its own test that drives the clock deliberately.
    boardPollIntervalProvider.overrideWithValue(null),
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
  testWidgets('an empty board says so rather than showing a blank screen', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(jobs: FakeJobsDataSource()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing waiting'), findsOneWidget);
    expect(find.textContaining('Nayan'), findsOneWidget);
  });

  testWidgets('the board shows a job, and the phone number is NOT on it', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(jobs: FakeJobsDataSource(board: <JobOffer>[offer()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paradise Biryani'), findsOneWidget);
    expect(find.text('Collect ₹720 in cash'), findsOneWidget);
    // The customer's number arrives only after committing — the board never
    // carries it, and that split is enforced in Postgres too.
    expect(find.text('+919876543210'), findsNothing);
  });

  testWidgets('taking a job replaces the board with the job in hand', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take this job'));
    await tester.pumpAndSettle();

    expect(jobs.mine.length, 1);
    expect(find.text('Your job'), findsOneWidget);
    expect(find.text('Collect from'), findsOneWidget);
    // Now that it is theirs, the number is there.
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Take this job'), findsNothing);
  });

  testWidgets('losing the race is said plainly, and takes nothing on', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    )..claimLoses = true;
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take this job'));
    await tester.pumpAndSettle();

    expect(find.text('Another partner just took that one.'), findsOneWidget);
    expect(jobs.mine, isEmpty);
  });

  testWidgets('a job that is still cooking offers no code to type', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          mine: <Job>[job(orderStatus: 'preparing')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not packed yet'), findsOneWidget);
    // The CTA variant of ZopiqButton is a FilledButton underneath. Disabled is
    // the assertion that matters — the label alone would pass even if the button
    // still fired a call the database would refuse.
    final FilledButton button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Not packed yet'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the pickup code hands the bag over; a wrong one does not', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(mine: <Job>[job()]);
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // Wrong code first — refused in the database's own words.
    await tester.tap(find.text('Enter pickup code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Confirm pickup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('doesn\'t match'), findsOneWidget);
    expect(jobs.mine.single.state, JobState.claimed);

    // Then the right one.
    await tester.tap(find.text('Enter pickup code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5896');
    await tester.tap(find.text('Confirm pickup'));
    await tester.pumpAndSettle();

    expect(jobs.mine.single.state, JobState.pickedUp);
    // Carrying it now: the screen flips from the shop to the doorstep.
    expect(find.text('Deliver to'), findsOneWidget);
    expect(find.text('Mark delivered'), findsOneWidget);
  });

  testWidgets('delivering ends the job and returns the rider to the board', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      mine: <Job>[job(state: JobState.pickedUp, orderStatus: 'out_for_delivery')],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark delivered'));
    await tester.pumpAndSettle();
    // Cash orders get the reminder that the money is the point. Matched exactly,
    // because the card behind the dialog also mentions the same amount.
    expect(
      find.text('Make sure you have collected ₹720 in cash.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delivered'));
    await tester.pumpAndSettle();

    expect(jobs.mine.single.state, JobState.delivered);
    expect(find.text('Available jobs'), findsOneWidget);
  });

  testWidgets('dropping an unstarted job puts it back on the board', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(mine: <Job>[job()]);
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drop this job'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Drop it'));
    await tester.pumpAndSettle();

    expect(jobs.mine, isEmpty);
    expect(find.text('Take this job'), findsOneWidget);
  });
}
