import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_rider/app/rider_app.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

import '../../support/fakes.dart';

Widget _app({required FakeRiderAuthDataSource auth}) => ProviderScope(
  overrides: <Override>[
    riderAuthDataSourceProvider.overrideWithValue(auth),
    jobsDataSourceProvider.overrideWithValue(FakeJobsDataSource()),
    // Signing in lands on the board, so these tests mount it too.
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
  testWidgets('a signed-out rider lands on sign-in, not on the board', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(auth: FakeRiderAuthDataSource()));
    await tester.pumpAndSettle();

    expect(find.text('Partner Sign In'), findsOneWidget);
    expect(find.text('Jobs'), findsNothing);
  });

  testWidgets('a good code for a partner reaches the board', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeRiderAuthDataSource auth = FakeRiderAuthDataSource();
    await tester.pumpWidget(_app(auth: auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nayan@siteonlab.com');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();
    expect(auth.lastCodeSentTo, 'nayan@siteonlab.com');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify & Access Shift'));
    await tester.pumpAndSettle();

    expect(find.text('Jobs'), findsWidgets);
  });

  testWidgets(
    'a good code for someone who does not ride gets a screen, not an error',
    (WidgetTester tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(
        _app(auth: FakeRiderAuthDataSource(isPartner: false)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'someone@else.com');
      await tester.tap(find.text('Send Verification Code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify & Access Shift'));
      await tester.pumpAndSettle();

      // Not bounced back to sign in, which would let them log in forever.
      expect(find.text('Account Not Onboarded'), findsOneWidget);
      expect(find.text('Jobs'), findsNothing);
    },
  );

  testWidgets('a wrong code says so and stays put', (WidgetTester tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app(auth: FakeRiderAuthDataSource()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nayan@siteonlab.com');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Verify & Access Shift'));
    await tester.pumpAndSettle();

    expect(find.textContaining('didn\'t work'), findsOneWidget);
    expect(find.text('Jobs'), findsNothing);
  });

  testWidgets('the auth service\'s own reason reaches the rider', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        auth: FakeRiderAuthDataSource()
          ..sendFailsWith =
              'For security purposes, you can only request this after 54 seconds.',
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nayan@siteonlab.com');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // Passed through, not replaced. A rider can wait 54 seconds; they
    // cannot do anything with 'please try again'.
    expect(
      find.text(
        'For security purposes, you can only request this after 54 seconds.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a dead network is named as one, not blamed on the code', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(auth: FakeRiderAuthDataSource()..sendThrowsNetworkError = true),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nayan@siteonlab.com');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // The shape of the bug that cost a release build: no INTERNET
    // permission looks exactly like this, and the old copy blamed the send.
    expect(
      find.text('We couldn\'t reach Zopiqnow. Check your connection.'),
      findsOneWidget,
    );
  });
}
