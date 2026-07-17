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

Future<void> _openHistory(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
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
    await _openHistory(tester);

    expect(find.byType(HistoryPage), findsOneWidget);

    // The two finished orders show; the open one belongs to the queue.
    expect(find.text('ZPQ-DONE'), findsOneWidget);
    expect(find.text('ZPQ-GONE'), findsOneWidget);
    expect(find.text('ZPQ-OPEN'), findsNothing);
  });

  testWidgets('the outcome filter narrows the list', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
      orders: <VendorOrder>[
        order(id: 'ZPQ-DONE', status: OrderStatus.delivered),
        order(id: 'ZPQ-GONE', status: OrderStatus.cancelled),
      ],
    );
    addTearDown(orders.dispose);

    await tester.pumpWidget(_app(orders: orders));
    await _openHistory(tester);

    // Both are here to begin with.
    expect(find.text('ZPQ-DONE'), findsOneWidget);
    expect(find.text('ZPQ-GONE'), findsOneWidget);

    // Tap the "Cancelled" outcome chip — the first "Cancelled" in the tree is
    // the chip, which sits above the tickets.
    await tester.tap(find.text('Cancelled').first);
    await tester.pumpAndSettle();

    // Only the cancelled order survives the filter.
    expect(find.text('ZPQ-GONE'), findsOneWidget);
    expect(find.text('ZPQ-DONE'), findsNothing);
  });

  testWidgets('searching by id narrows the list', (WidgetTester tester) async {
    _tallSurface(tester);
    final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
      orders: <VendorOrder>[
        order(id: 'ZPQ-1111', status: OrderStatus.delivered),
        order(id: 'ZPQ-2222', status: OrderStatus.delivered),
      ],
    );
    addTearDown(orders.dispose);

    await tester.pumpWidget(_app(orders: orders));
    await _openHistory(tester);

    await tester.enterText(find.byType(TextField), '2222');
    // Past the 300ms search debounce.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('ZPQ-2222'), findsOneWidget);
    expect(find.text('ZPQ-1111'), findsNothing);
  });

  testWidgets('tapping a ticket opens the bill breakdown', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
      orders: <VendorOrder>[
        order(
          id: 'ZPQ-BILL',
          status: OrderStatus.delivered,
          total: 720,
          subtotal: 644,
          deliveryFee: 40,
          taxes: 36,
        ),
      ],
    );
    addTearDown(orders.dispose);

    await tester.pumpWidget(_app(orders: orders));
    await _openHistory(tester);

    await tester.tap(find.text('ZPQ-BILL'));
    await tester.pumpAndSettle();

    // The detail sheet lays out the bill the customer agreed to.
    expect(find.text('Item total'), findsOneWidget);
    expect(find.text('Delivery fee'), findsOneWidget);
    expect(find.text('Taxes'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
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
    await _openHistory(tester);

    expect(find.text('No orders in this period'), findsOneWidget);
  });
}
