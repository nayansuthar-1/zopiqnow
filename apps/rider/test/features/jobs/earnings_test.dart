import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

Widget _app({Rider? signedInAs = testRider, required FakeJobsDataSource jobs}) =>
    ProviderScope(
      overrides: <Override>[
        riderAuthDataSourceProvider.overrideWithValue(
          FakeRiderAuthDataSource(signedInAs: signedInAs),
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
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openEarnings(WidgetTester tester) async {
  await tester.tap(find.text('Earnings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the shell reaches earnings and profile', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(jobs: FakeJobsDataSource()));
    await tester.pumpAndSettle();

    expect(find.text('Scanning for New Orders'), findsOneWidget);

    await _openEarnings(tester);
    expect(find.text('TODAY\'S EARNINGS'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Nayan'), findsOneWidget);
    // Sign-out left the jobs app bar and lives here now.
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('a delivered job shows its pay AND the sum that produced it', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          mine: <Job>[job(state: JobState.delivered)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    // ₹25 base + 4.2 km × ₹5 = ₹46. The rider can check every part of that.
    expect(find.text('₹46'), findsWidgets);
    expect(find.text('₹25 + 4.2 km × ₹5'), findsOneWidget);
    expect(find.text('1 delivery'), findsWidgets);
  });

  testWidgets('an unmeasured job says base fee only, never a confident 0 km', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          mine: <Job>[
            job(state: JobState.delivered, distanceKm: null, riderPay: 25),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    expect(
      find.textContaining('base fee only'),
      findsOneWidget,
      reason: 'a missing coordinate is unknown distance, not zero distance',
    );
    expect(find.textContaining('0 km'), findsNothing);
  });

  testWidgets('a job in hand is not income until it is delivered', (
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
    await _openEarnings(tester);

    // Claimed, priced, and worth nothing yet — a rider who saw their total rise
    // at claim would have been paid for a delivery they might still fail.
    expect(find.text('₹0'), findsWidgets);
    expect(find.textContaining('No completed deliveries yet'), findsOneWidget);
  });

  testWidgets('with no payouts yet, the section is absent rather than empty', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(jobs: FakeJobsDataSource(mine: <Job>[job(state: JobState.delivered)])),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    // A first-week rider should not see a "Payouts" heading over nothing —
    // that reads as broken, not as not-yet.
    expect(find.text('Weekly Payouts'), findsNothing);
  });

  testWidgets('a pending payout says what is owed and that it is on the way', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(jobs: FakeJobsDataSource(payouts: <Payout>[payout()])),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    expect(find.text('Weekly Payouts'), findsOneWidget);
    expect(find.text('₹132 Processing'), findsOneWidget);
    expect(find.text('Processing Payment'), findsOneWidget);
    // The week, collapsed to one month name.
    expect(find.text('13–19 Jul'), findsOneWidget);
    expect(find.text('3 deliveries'), findsOneWidget);
  });

  testWidgets('a paid payout shows the bank reference and drops off the owed sum', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(jobs: FakeJobsDataSource(payouts: <Payout>[payout(isPaid: true)])),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    expect(find.text('Transfer Completed'), findsOneWidget);
    // The rider needs this to ask their bank about a payment that never landed.
    expect(find.textContaining('UTR123456789'), findsOneWidget);
    expect(find.textContaining('Processing'), findsNothing);
  });

  testWidgets('a period spanning two months names both', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          payouts: <Payout>[
            payout(
              periodStart: DateTime(2026, 7, 27),
              periodEnd: DateTime(2026, 8, 2),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openEarnings(tester);

    expect(find.text('27 Jul–2 Aug'), findsOneWidget);
  });

  testWidgets('delivering moves the money into today\'s total', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeJobsDataSource jobs = FakeJobsDataSource(
      board: <JobOffer>[offer()],
    );
    await tester.pumpWidget(_app(jobs: jobs));
    await tester.pumpAndSettle();

    // The whole run, end to end, through the five taps 0049 requires: claim,
    // arrive, code, arrive, code. Money only moves on the last one.
    await tester.tap(find.text('Claim & Accept Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I\'ve Arrived at the Restaurant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter Pickup Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5896');
    await tester.pumpAndSettle();
    await tester.tap(find.text('I\'ve Arrived at the Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter Delivery Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '4321');
    await tester.pumpAndSettle();

    await _openEarnings(tester);
    expect(find.text('₹46'), findsWidgets);
  });
}
