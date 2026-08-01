import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/core/launcher.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

/// Handing off to the map and the dialler.
///
/// These assert the URI the app produces and stop there. Whether a particular
/// phone has a maps app is not something a widget test can know, and pretending
/// otherwise would be testing Android rather than us.

Widget _app({
  required FakeJobsDataSource jobs,
  required FakeLauncher launcher,
}) => ProviderScope(
  overrides: <Override>[
    riderAuthDataSourceProvider.overrideWithValue(
      FakeRiderAuthDataSource(signedInAs: testRider),
    ),
    jobsDataSourceProvider.overrideWithValue(jobs),
    launcherProvider.overrideWithValue(launcher),
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
  testWidgets('collecting navigates to the kitchen, not the customer', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher();
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(mine: <Job>[job()]),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();

    // Since B3, a job with coordinates opens the in-app map first; the external
    // hand-off is a button on that page rather than the whole of Navigate. This
    // test asserted the old single-step behaviour and so stopped exercising
    // anything the moment the map landed.
    await tester.tap(find.text('Open in Maps'));
    await tester.pumpAndSettle();

    // Unwind the map route before the test ends.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The restaurant's pin, labelled with the restaurant. Sending a rider to
    // the customer's door to collect food would be the whole feature backwards.
    expect(
      launcher.opened.single,
      'geo:24.6061,72.3283?q=24.6061,72.3283(Paradise%20Biryani)',
    );
  });

  testWidgets('carrying navigates to the customer instead', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher();
    await tester.pumpWidget(
      _app(
        jobs: FakeJobsDataSource(
          mine: <Job>[job(state: JobState.pickedUp)],
        ),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Maps'));
    await tester.pumpAndSettle();

    // Unwind the map route before the test ends.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(launcher.opened.single, contains('geo:24.5881,72.3163'));
    expect(launcher.opened.single, contains('Banjara%20Hills'));
  });

  testWidgets('a kitchen with no map location falls back to its address', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher();
    await tester.pumpWidget(
      _app(
        // *Both* ends unmapped, which is what the fallback actually requires.
        // Nulling only the restaurant left the customer's pin in place, so the
        // job was still mappable and this opened the map page instead of falling
        // back — the assertion below then had nothing to read.
        jobs: FakeJobsDataSource(
          mine: <Job>[
            job(
              restaurantLat: null,
              restaurantLng: null,
              deliverLat: null,
              deliverLng: null,
            ),
          ],
        ),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    // No map to open, so Navigate is the hand-off itself — no intermediate page.
    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();

    // A text search is worse than a pin and far better than a dead button.
    expect(launcher.opened.single, 'geo:0,0?q=Paradise%20Biryani');
  });

  testWidgets('calling opens the dialler with the customer\'s number', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher();
    await tester.pumpWidget(
      _app(
        // Carrying, and that is load-bearing. Since B5 the call button rings
        // whichever end of the ride the rider is on — the kitchen while
        // collecting, the customer while carrying — so a *claimed* job's button
        // says "Call Restaurant" and dials the kitchen. This test wants the
        // customer, so the job has to be one the rider has picked up.
        jobs: FakeJobsDataSource(mine: <Job>[job(state: JobState.pickedUp)]),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Call Customer'));
    await tester.pumpAndSettle();

    // The '+' is percent-encoded: in a URI it would otherwise read as a space
    // and the country code would be lost.
    expect(launcher.opened.single, 'tel:%2B919876543210');
  });

  testWidgets('no number yet means no call button to press', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher();
    await tester.pumpWidget(
      _app(
        // Carrying, so the button is aimed at the customer — and the customer
        // is the end that has no number. While *collecting* the button rings
        // the kitchen, whose number is always on file, so a claimed job could
        // never exercise the disabled case this test is named for.
        jobs: FakeJobsDataSource(
          mine: <Job>[job(state: JobState.pickedUp, customerPhone: '')],
        ),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    // Disabled, not hidden — so it is still findable, and tapping it is the
    // point: nothing must happen.
    await tester.tap(find.text('Call Customer'));
    await tester.pumpAndSettle();

    expect(launcher.opened, isEmpty);
  });

  testWidgets('a phone with no maps app says so rather than doing nothing', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeLauncher launcher = FakeLauncher()..succeeds = false;
    await tester.pumpWidget(
      _app(
        // Unmapped at both ends, so Navigate is the hand-off itself. A job with
        // coordinates would open the in-app map and never reach the launcher —
        // which is what made this assertion unreachable.
        jobs: FakeJobsDataSource(
          mine: <Job>[
            job(
              restaurantLat: null,
              restaurantLng: null,
              deliverLat: null,
              deliverLng: null,
            ),
          ],
        ),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Navigate'));
    await tester.pump();

    expect(find.text('No maps app could open that address.'), findsOneWidget);
  });
}
