import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/analytics/domain/entities/analytics_summary.dart';
import 'package:zopiq_vendor/features/analytics/presentation/pages/analytics_page.dart';
import 'package:zopiq_vendor/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';

import '../../support/fakes.dart';

Widget _app(FakeAnalyticsDataSource analytics) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    notificationsDataSourceProvider.overrideWithValue(FakeNotificationsDataSource()),
    analyticsDataSourceProvider.overrideWithValue(analytics),
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

Future<void> _openAnalytics(
  WidgetTester tester,
  FakeAnalyticsDataSource analytics,
) async {
  await tester.pumpWidget(_app(analytics));
  await tester.pumpAndSettle();
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Analytics'));
  await tester.pumpAndSettle();
  expect(find.byType(AnalyticsPage), findsOneWidget);
}

void main() {
  testWidgets('a window with sales shows the headline numbers and best-sellers', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeAnalyticsDataSource analytics = FakeAnalyticsDataSource(
      summary: AnalyticsSummary(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 30),
        orderCount: 42,
        itemsSold: 96,
        avgOrderValue: 380,
        topDishes: const <DishSales>[
          DishSales(name: 'Chicken Biryani', qty: 60, revenue: 18000),
          DishSales(name: 'Paneer Tikka', qty: 24, revenue: 6000),
        ],
        hourly: const <HourBucket>[
          HourBucket(hour: 13, orders: 10),
          HourBucket(hour: 20, orders: 32),
        ],
      ),
    );

    await _openAnalytics(tester, analytics);

    // The three headline figures and a best-seller row are on screen.
    expect(find.text('42'), findsOneWidget);
    expect(find.text('96'), findsOneWidget);
    expect(find.text('₹380'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);
    expect(find.text('60 sold'), findsOneWidget);
  });

  testWidgets('an empty window shows the nothing-yet message, not zeros', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeAnalyticsDataSource analytics = FakeAnalyticsDataSource();

    await _openAnalytics(tester, analytics);

    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.text('Best sellers'), findsNothing);
  });
}
