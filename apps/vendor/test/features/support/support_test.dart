import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:zopiq_vendor/features/support/presentation/pages/support_page.dart';

import '../../support/fakes.dart';

Widget _app() => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    notificationsDataSourceProvider.overrideWithValue(FakeNotificationsDataSource()),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the support room lists answers and shows the restaurant id', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();

    expect(find.byType(SupportPage), findsOneWidget);
    expect(find.text('Common questions'), findsOneWidget);
    // The restaurant id is on screen so the vendor can quote it to support.
    expect(find.text(testVendor.restaurantId), findsOneWidget);

    // A question opens to reveal its answer.
    expect(find.text('When do I get paid?'), findsOneWidget);
    await tester.tap(find.text('When do I get paid?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rolled up every Monday'), findsOneWidget);
  });
}
