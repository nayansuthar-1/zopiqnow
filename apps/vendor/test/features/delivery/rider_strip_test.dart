import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/delivery/domain/entities/order_delivery.dart';
import 'package:zopiq_vendor/features/delivery/presentation/providers/delivery_providers.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';

import '../../support/fakes.dart';

Widget _app({
  required List<VendorOrder> orders,
  Map<String, OrderDelivery> deliveries = const <String, OrderDelivery>{},
}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(
      FakeVendorOrderDataSource(orders: orders),
    ),
    deliveryDataSourceProvider.overrideWithValue(
      FakeDeliveryDataSource(active: deliveries),
    ),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    notificationsDataSourceProvider.overrideWithValue(
      FakeNotificationsDataSource(),
    ),
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

Future<void> _openQueue(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Orders'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a ticket with no rider claimed looks exactly as it always did', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(orders: <VendorOrder>[order(status: OrderStatus.readyForPickup)]),
    );
    await _openQueue(tester);

    expect(find.text('ZPQ-1042'), findsOneWidget);
    expect(find.byIcon(Icons.delivery_dining_rounded), findsNothing);
  });

  testWidgets('the pickup code appears only once the food is packed', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    // Claimed, but the kitchen is still cooking — the rider is riding over and
    // there is nothing yet to hand across the counter.
    await tester.pumpWidget(
      _app(
        orders: <VendorOrder>[order(status: OrderStatus.preparing)],
        deliveries: <String, OrderDelivery>{'ZPQ-1042': delivery()},
      ),
    );
    await _openQueue(tester);

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('On the way to collect'), findsOneWidget);
    expect(find.text('5896'), findsNothing);
  });

  testWidgets('packed and claimed shows the code to read out', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        orders: <VendorOrder>[order(status: OrderStatus.readyForPickup)],
        deliveries: <String, OrderDelivery>{'ZPQ-1042': delivery()},
      ),
    );
    await _openQueue(tester);

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Read the code to hand over'), findsOneWidget);
    expect(find.text('5896'), findsOneWidget);
  });

  testWidgets('once picked up the code is spent and comes off the ticket', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(
      _app(
        orders: <VendorOrder>[order(status: OrderStatus.outForDelivery)],
        deliveries: <String, OrderDelivery>{
          'ZPQ-1042': delivery(state: DeliveryState.pickedUp),
        },
      ),
    );
    await _openQueue(tester);

    expect(find.text('Picked up'), findsOneWidget);
    expect(find.text('5896'), findsNothing);
  });
}
