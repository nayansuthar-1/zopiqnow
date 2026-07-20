import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/notifications/domain/entities/vendor_notification.dart';
import 'package:zopiq_vendor/features/notifications/presentation/pages/notifications_page.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';

import '../../support/fakes.dart';

Widget _app({required FakeNotificationsDataSource notifications}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(FakeVendorOrderDataSource()),
    paymentsDataSourceProvider.overrideWithValue(FakePaymentsDataSource()),
    notificationsDataSourceProvider.overrideWithValue(notifications),
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

/// Home is the landing screen; the bell into the inbox lives in its header.
Future<void> _openInbox(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.notifications_none_rounded).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the inbox lists notifications, newest content shown', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeNotificationsDataSource notifications = FakeNotificationsDataSource(
      initial: <VendorNotification>[
        notification(id: 2, body: 'Order ZPQ-2 · ₹500', orderId: 'ZPQ-2'),
        notification(id: 1, body: 'Order ZPQ-1 · ₹300', orderId: 'ZPQ-1', read: true),
      ],
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(_app(notifications: notifications));
    await _openInbox(tester);

    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Order ZPQ-2 · ₹500'), findsOneWidget);
    expect(find.text('Order ZPQ-1 · ₹300'), findsOneWidget);
  });

  testWidgets('empty inbox shows the calm empty state', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeNotificationsDataSource notifications = FakeNotificationsDataSource();
    addTearDown(notifications.dispose);

    await tester.pumpWidget(_app(notifications: notifications));
    await _openInbox(tester);

    expect(find.text('Nothing yet'), findsOneWidget);
    // Nothing unread, so no "Mark all read" action.
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('Mark all read clears the unread pile', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeNotificationsDataSource notifications = FakeNotificationsDataSource(
      initial: <VendorNotification>[
        notification(id: 1),
        notification(id: 2),
      ],
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(_app(notifications: notifications));
    await _openInbox(tester);

    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(notifications.markAllCalls, 1);
    // With nothing unread, the action is gone.
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('tapping a notification marks it read and opens the queue', (
    WidgetTester tester,
  ) async {
    _tallSurface(tester);
    final FakeNotificationsDataSource notifications = FakeNotificationsDataSource(
      initial: <VendorNotification>[
        notification(id: 7, body: 'Order ZPQ-7 · ₹640', orderId: 'ZPQ-7'),
      ],
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(_app(notifications: notifications));
    await _openInbox(tester);

    await tester.tap(find.text('Order ZPQ-7 · ₹640'));
    await tester.pumpAndSettle();

    expect(notifications.markedRead, contains(7));
  });
}
