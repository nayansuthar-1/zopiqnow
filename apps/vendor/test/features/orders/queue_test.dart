import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiq_vendor/app/vendor_app.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/not_staff_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/pages/sign_in_page.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/pages/queue_page.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

import '../../support/fakes.dart';

Widget _app({
  required FakeVendorOrderDataSource orders,
  FakeVendorAuthDataSource? auth,
}) => ProviderScope(
  overrides: <Override>[
    vendorAuthDataSourceProvider.overrideWithValue(
      auth ?? FakeVendorAuthDataSource(signedInAs: testVendor),
    ),
    vendorOrderDataSourceProvider.overrideWithValue(orders),
    // The age clock is a `Stream.periodic`, which never completes — a pending
    // timer the test binding rightly refuses to end a test on. Ages are computed
    // at build from `placedAt`, so a clock that never ticks changes nothing here
    // except that the test terminates.
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
  group('the queue', () {
    testWidgets('a new order arrives with what to cook and who to call', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order()],
      );
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      expect(find.byType(QueuePage), findsOneWidget);
      expect(find.text('Paradise Biryani'), findsOneWidget);
      expect(find.text('1 new · 1 in the queue'), findsOneWidget);

      // What to cook.
      expect(find.text('2×'), findsOneWidget);
      expect(find.text('Chicken Biryani'), findsOneWidget);

      // Who to call, and what to collect — a cash order means the rider carries
      // a number, not just food.
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('Collect ₹720 in cash'), findsOneWidget);

      // How long it has been sitting there, which is what a kitchen is judged on.
      expect(find.text('4 min'), findsOneWidget);

      expect(find.text('Accept order'), findsOneWidget);
    });

    testWidgets('accepting an order moves it on, and the button with it', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order()],
      );
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept order'));
      await tester.pumpAndSettle();

      // The new status was not written locally — it came back on the stream,
      // because the database is what decides what an order's status is.
      expect(find.text('Accept order'), findsNothing);
      expect(find.text('Start preparing'), findsOneWidget);
      // "0 new" is not worth saying. The header stops shouting once nothing is
      // waiting on a human.
      expect(find.text('1 in the queue'), findsOneWidget);
    });

    testWidgets('a delivered order leaves the queue', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(status: OrderStatus.outForDelivery)],
      );
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark delivered'));
      await tester.pumpAndSettle();

      expect(find.text('All caught up'), findsOneWidget);
      expect(find.text('ZPQ-1042'), findsNothing);
    });

    testWidgets('a move the order service refuses is shown in its own words', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order()],
      )..refusal = 'An order that is cancelled cannot become accepted.';
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept order'));
      await tester.pumpAndSettle();

      // The database's sentence, not ours. "Please try again" would tell the
      // kitchen nothing about an order that someone else already cancelled.
      expect(
        find.text('An order that is cancelled cannot become accepted.'),
        findsOneWidget,
      );
      // And the ticket did not move.
      expect(find.text('Accept order'), findsOneWidget);
    });

    testWidgets('an order with the rider can no longer be cancelled', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(status: OrderStatus.outForDelivery)],
      );
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      // The food has left the building. That is a refund conversation, not a
      // status change — and `set_order_status` would refuse it anyway.
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Mark delivered'), findsOneWidget);
    });

    testWidgets('a prepaid order does not tell the rider to collect cash', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource(
        orders: <VendorOrder>[order(paymentMethod: PaymentMethod.upi)],
      );
      addTearDown(orders.dispose);

      await tester.pumpWidget(_app(orders: orders));
      await tester.pumpAndSettle();

      expect(find.textContaining('Collect'), findsNothing);
      expect(find.text('Paid online · ₹720'), findsOneWidget);
    });
  });

  group('opening and closing the kitchen', () {
    testWidgets('pausing orders flips the bar and writes it', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource();
      addTearDown(orders.dispose);
      final FakeVendorAuthDataSource auth = FakeVendorAuthDataSource(
        signedInAs: testVendor,
      );

      await tester.pumpWidget(_app(orders: orders, auth: auth));
      await tester.pumpAndSettle();

      // Open to begin with — the seeded vendor is accepting orders.
      expect(find.text('Taking orders'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The bar flips optimistically, and the write carried the new value.
      expect(find.text('Orders paused'), findsOneWidget);
      expect(auth.lastAcceptingOrders, isFalse);
    });

    testWidgets('a toggle the database refuses reverts and says so', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource();
      addTearDown(orders.dispose);
      final FakeVendorAuthDataSource auth = FakeVendorAuthDataSource(
        signedInAs: testVendor,
      )..failAcceptingOrders = true;

      await tester.pumpWidget(_app(orders: orders, auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The write failed, so the bar goes back to open rather than lying that
      // the kitchen is closed while orders still arrive.
      expect(find.text('Taking orders'), findsOneWidget);
      expect(find.text('Orders paused'), findsNothing);
      expect(find.textContaining('couldn\'t pause orders'), findsOneWidget);
    });
  });

  group('who is allowed in', () {
    testWidgets('a signed-out visitor gets the sign-in screen, not the queue', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource();
      addTearDown(orders.dispose);

      await tester.pumpWidget(
        _app(orders: orders, auth: FakeVendorAuthDataSource()),
      );
      await tester.pumpAndSettle();

      // Every screen in this app is somebody's order book. There is no
      // unguarded route.
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(QueuePage), findsNothing);
    });

    testWidgets('a real person who is not staff is told so, not failed', (
      WidgetTester tester,
    ) async {
      _tallSurface(tester);
      final FakeVendorOrderDataSource orders = FakeVendorOrderDataSource();
      addTearDown(orders.dispose);

      await tester.pumpWidget(
        _app(orders: orders, auth: FakeVendorAuthDataSource(staff: false)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'someone@example.com');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      // They proved they own that mailbox. It just isn't a restaurant — which is
      // a screen, not an error, and certainly not a login loop.
      expect(find.byType(NotStaffPage), findsOneWidget);
      expect(
        find.textContaining('isn\'t registered to a restaurant'),
        findsOneWidget,
      );
    });
  });

  group('the contract with the database', () {
    test('every status sends the wire value the check constraint allows', () {
      // `name` would send `outForDelivery`, which Postgres would refuse —
      // correctly, and at the worst possible moment.
      expect(OrderStatus.outForDelivery.wire, 'out_for_delivery');
      for (final OrderStatus s in OrderStatus.values) {
        expect(OrderStatus.fromWire(s.wire), s);
      }
    });

    test('the button offers exactly what set_order_status will accept', () {
      // Mirrors the transition table in migration 0009. A button that is usually
      // refused is a button nobody trusts.
      expect(OrderStatus.placed.next, OrderStatus.accepted);
      expect(OrderStatus.accepted.next, OrderStatus.preparing);
      expect(OrderStatus.preparing.next, OrderStatus.outForDelivery);
      expect(OrderStatus.outForDelivery.next, OrderStatus.delivered);
      expect(OrderStatus.delivered.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);

      expect(OrderStatus.preparing.canCancel, isTrue);
      expect(OrderStatus.outForDelivery.canCancel, isFalse);
    });

    test('a ticket\'s age reads the way a kitchen talks', () {
      expect(formatAge(const Duration(seconds: 20)), 'just now');
      expect(formatAge(const Duration(minutes: 4)), '4 min');
      expect(formatAge(const Duration(minutes: 72)), '1 hr 12 min');
      expect(formatAge(const Duration(hours: 2)), '2 hr');
    });
  });
}
