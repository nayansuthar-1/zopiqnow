import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

/// Carrying more than one job at a time.
///
/// The database always allowed this — 8b-4 left concurrent claims uncapped on
/// purpose, because batching orders from one street is what the work actually
/// looks like. The app was the only thing enforcing one at a time.

Widget _app({required FakeJobsDataSource jobs}) => ProviderScope(
  overrides: <Override>[
    riderAuthDataSourceProvider.overrideWithValue(
      FakeRiderAuthDataSource(signedInAs: testRider),
    ),
    jobsDataSourceProvider.overrideWithValue(jobs),
    boardPollIntervalProvider.overrideWithValue(null),
  ],
  child: const RiderApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a run shows every job in hand, not just the first', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          mine: <Job>[
            job(orderId: 'ZPQ-A'),
            job(orderId: 'ZPQ-B', state: JobState.pickedUp),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Your Run'), findsOneWidget);
    expect(find.textContaining('ZPQ-A'), findsOneWidget);
    expect(find.textContaining('ZPQ-B'), findsOneWidget);
    expect(find.text('Your Run (2 Active)'), findsOneWidget);
  });

  testWidgets('the run is ordered by what can be acted on now', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          // Deliberately supplied worst-first, so passing means the sort ran.
          mine: <Job>[
            job(orderId: 'ZPQ-COOKING', orderStatus: 'preparing'),
            job(orderId: 'ZPQ-CARRYING', state: JobState.pickedUp),
            job(orderId: 'ZPQ-PACKED'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    double y(String id) => tester.getTopLeft(find.textContaining(id)).dy;

    // Packed and waiting on a counter, then what is already on the bike, then
    // what the kitchen has not finished. Not a route — the app knows two dots
    // and nothing about the roads between them.
    expect(y('ZPQ-PACKED'), lessThan(y('ZPQ-CARRYING')));
    expect(y('ZPQ-CARRYING'), lessThan(y('ZPQ-COOKING')));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('On Bike'), findsOneWidget);
    expect(find.text('Cooking'), findsOneWidget);
  });

  testWidgets('a rider can reach the board while carrying, and take a second', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer(orderId: 'ZPQ-NEW')],
      mine: <Job>[job(orderId: 'ZPQ-FIRST')],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // Opens on the run, not the board — the old instinct survives.
    expect(find.text('Claim & Accept Job'), findsNothing);

    await tester.tap(find.text('Available Board'));
    await tester.pumpAndSettle();
    expect(find.text('Claim & Accept Job'), findsOneWidget);

    await tester.tap(find.text('Claim & Accept Job'));
    await tester.pumpAndSettle();

    expect(jobs.mine.length, 2);
    expect(find.text('Your Run (2 Active)'), findsOneWidget);
  });

  testWidgets('finishing the last job returns to the board on its own', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      mine: <Job>[job(orderId: 'ZPQ-ONLY', state: JobState.pickedUp)],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I\'ve Arrived at the Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter Delivery Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '4321');
    await tester.pumpAndSettle();

    // The switch disappears with the run that justified it, leaving the plain
    // board a free rider sees.
    expect(find.text('Scanning for New Orders'), findsOneWidget);
    expect(find.text('Available Board'), findsNothing);
  });

  testWidgets('dropping one job leaves the rest of the run alone', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      mine: <Job>[job(orderId: 'ZPQ-A'), job(orderId: 'ZPQ-B')],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // Two identical cards, so the first "Drop this job" belongs to ZPQ-A.
    await tester.tap(find.text('Drop this job').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop Job'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ZPQ-A'), findsNothing);
    expect(find.textContaining('ZPQ-B'), findsOneWidget);
    expect(find.text('Your Run (1 Active)'), findsOneWidget);
  });
}
