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

    expect(find.text('Scanning for New Orders'), findsOneWidget);
    // The rider is addressed by name — now both in the app-bar greeting and in
    // the empty-state line, so at least once rather than exactly once.
    expect(find.textContaining('Nayan'), findsWidgets);
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
    expect(find.text('Collect Cash: ₹720'), findsOneWidget);
    // The customer's number arrives only after committing — the board never
    // carries it, and that split is enforced in Postgres too.
    expect(find.text('+919876543210'), findsNothing);
  });

  testWidgets('taking a job opens the run, with the board a tap away', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Claim & Accept Job'));
    await tester.pumpAndSettle();

    expect(jobs.mine.length, 1);
    expect(find.textContaining('Your Run'), findsOneWidget);
    expect(find.text('PICK UP FROM'), findsOneWidget);
    // Now that it is theirs, the number is there.
    expect(find.text('+919876543210'), findsOneWidget);
    // The board is no longer showing — but it is reachable, which is what
    // changed when stacked deliveries arrived.
    expect(find.text('Claim & Accept Job'), findsNothing);
    expect(find.text('Available Board'), findsOneWidget);
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

    await tester.tap(find.text('Claim & Accept Job'));
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
          // Standing in the shop, watching the kitchen. This is the only step in
          // the run where the button is allowed to sit disabled.
          mine: <Job>[
            job(state: JobState.arrivedAtRestaurant, orderStatus: 'preparing'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order Still Cooking...'), findsOneWidget);
    // The CTA variant of ZopiqButton is a FilledButton underneath. Disabled is
    // the assertion that matters — the label alone would pass even if the button
    // still fired a call the database would refuse.
    final FilledButton button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Order Still Cooking...'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the pickup code hands the bag over; a wrong one does not', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      mine: <Job>[job(state: JobState.arrivedAtRestaurant)],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // Wrong code first — refused in the database's own words. The pin input
    // submits itself the moment a fourth digit lands, so entering the code is
    // the whole action; there is no separate confirm tap.
    await tester.tap(find.text('Enter Pickup Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0000');
    await tester.pumpAndSettle();

    expect(find.textContaining('doesn\'t match'), findsOneWidget);
    expect(jobs.mine.single.state, JobState.arrivedAtRestaurant);

    // Then the right one.
    await tester.tap(find.text('Enter Pickup Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5896');
    await tester.pumpAndSettle();

    expect(jobs.mine.single.state, JobState.pickedUp);
    // Carrying it now: the screen flips from the shop to the doorstep, and the
    // next move is the ride, not the hand-over.
    expect(find.text('DELIVER TO'), findsOneWidget);
    expect(find.text('I\'ve Arrived at the Customer'), findsOneWidget);
  });

  testWidgets('the two arrivals are steps, not decoration', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(mine: <Job>[job()]);
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // A freshly claimed job offers no code to type, however ready the food is:
    // 0049 refuses `confirm_pickup` from `claimed`, so a screen that offered it
    // would be offering a call the database is about to turn down.
    expect(find.text('Enter Pickup Code'), findsNothing);
    await tester.tap(find.text('I\'ve Arrived at the Restaurant'));
    await tester.pumpAndSettle();

    expect(jobs.mine.single.state, JobState.arrivedAtRestaurant);
    expect(find.text('Enter Pickup Code'), findsOneWidget);
  });

  testWidgets('delivering needs the customer\'s code, not the rider\'s word', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      mine: <Job>[
        job(state: JobState.pickedUp, orderStatus: 'out_for_delivery'),
      ],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I\'ve Arrived at the Customer'));
    await tester.pumpAndSettle();
    expect(jobs.mine.single.state, JobState.arrivedAtCustomer);

    await tester.tap(find.text('Enter Delivery Code'));
    await tester.pumpAndSettle();
    // Cash orders get the reminder that the money is the point, in the same
    // breath as the code — one screen, one doorstep, both jobs.
    expect(find.textContaining('Collect ₹720 in cash'), findsOneWidget);

    // A wrong code leaves the food in the rider's hands.
    await tester.enterText(find.byType(TextField), '0000');
    await tester.pumpAndSettle();
    expect(find.textContaining('doesn\'t match'), findsOneWidget);
    expect(jobs.mine.single.state, JobState.arrivedAtCustomer);

    await tester.tap(find.text('Enter Delivery Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4321');
    await tester.pumpAndSettle();

    expect(jobs.mine.single.state, JobState.delivered);
    expect(find.text('Scanning for New Orders'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(TextButton, 'Drop Job'));
    await tester.pumpAndSettle();

    expect(jobs.mine, isEmpty);
    expect(find.text('Claim & Accept Job'), findsOneWidget);
  });
}
