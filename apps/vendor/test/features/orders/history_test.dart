import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/pages/history_page.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/profile_providers.dart';

import '../../support/fakes.dart';

Widget _app({required FakeVendorOrderDataSource orders}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(orders),
    vendorRestaurantDataSourceProvider.overrideWithValue(
      FakeVendorRestaurantDataSource(),
    ),
    clockProvider.overrideWith((Ref ref) => const Stream<DateTime>.empty()),
  ],
  child: const VendorApp(),
);

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('history shows finished orders and hides the open ones', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
      orders: <VendorOrder>[
        order(id: 'ZPQ-OPEN', status: OrderStatus.preparing),
        order(id: 'ZPQ-DONE', status: OrderStatus.delivered),
        order(id: 'ZPQ-GONE', status: OrderStatus.cancelled),
      ],
    );
    addTearDown(orders.dispose);

    await tester.pumpWidget(_app(orders: orders));
    await tester.pumpAndSettle();

    // Move to the History tab.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryPage), findsOneWidget);

    // The two finished orders, with how they ended.
    expect(find.text('ZPQ-DONE'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('ZPQ-GONE'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);

    // The open one belongs to the queue, not here.
    expect(find.text('ZPQ-OPEN'), findsNothing);
  });

  testWidgets('history with nothing finished says so', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
      orders: <VendorOrder>[order(status: OrderStatus.placed)],
    );
    addTearDown(orders.dispose);

    await tester.pumpWidget(_app(orders: orders));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('No past orders yet'), findsOneWidget);
  });
}
