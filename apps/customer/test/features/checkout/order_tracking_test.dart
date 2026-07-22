import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_tracking_card.dart';

/// Placed at 7:00 pm with a 30-minute ETA, so the card promises 7:30 pm.
CustomerOrder _order(OrderStatus status) => CustomerOrder(
  id: 'ZPQ-1042',
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  status: status,
  placedAt: DateTime(2026, 7, 15, 19),
  deliveryTo: 'Banjara Hills, Hyderabad',
  etaMinutes: 30,
  paymentMethod: PaymentMethod.cod,
  subtotal: 580,
  deliveryFee: 0,
  taxes: 29,
  discount: 0,
  total: 609,
  lines: const <OrderLine>[
    OrderLine(
      menuItemId: 'r1-m1',
      name: 'Signature Chicken Biryani',
      unitPrice: 320,
      quantity: 1,
      lineTotal: 320,
    ),
  ],
);

/// The card with a *live* status pushed at it, which is the whole point: the
/// order was fetched once, and what the kitchen says afterwards arrives on the
/// stream. [live] null means the stream has said nothing yet.
Widget _card({
  required OrderStatus fetched,
  OrderStatus? live,
  OrderRider? rider,
}) => ProviderScope(
  overrides: <Override>[
    orderStatusProvider('ZPQ-1042').overrideWith(
      (Ref ref) => live == null
          ? const Stream<OrderStatus>.empty()
          : Stream<OrderStatus>.value(live),
    ),
    // Null is the ordinary answer — nobody has picked the order up, or the
    // restaurant delivers with its own staff.
    orderRiderProvider('ZPQ-1042').overrideWith((Ref ref) async => rider),
  ],
  child: MaterialApp(
    theme: ZopiqTheme.light,
    home: Scaffold(body: OrderTrackingCard(order: _order(fetched))),
  ),
);

void main() {
  group('order tracking card', () {
    testWidgets('a freshly placed order is waiting on the restaurant', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_card(fetched: OrderStatus.placed));
      await tester.pumpAndSettle();

      expect(
        find.text('Waiting for the restaurant to accept'),
        findsOneWidget,
      );
      // The ETA is the promise the order service made, rendered as the clock
      // time it amounts to — not a countdown that quietly slips.
      expect(find.text('Arriving by 7:30 pm'), findsOneWidget);

      // The whole journey is on screen, not just the step it is on.
      for (final OrderStatus s in OrderStatus.journey) {
        expect(find.text(s.label), findsOneWidget);
      }
    });

    testWidgets('the kitchen moves the order and the card follows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _card(fetched: OrderStatus.placed, live: OrderStatus.outForDelivery),
      );
      await tester.pumpAndSettle();

      // The status it was *fetched* with is stale the moment the stream speaks.
      expect(find.text('On its way to you'), findsOneWidget);
      expect(
        find.text('Waiting for the restaurant to accept'),
        findsNothing,
      );
    });

    testWidgets('a stream that says nothing leaves the fetched status standing', (
      WidgetTester tester,
    ) async {
      // A dropped socket costs the customer live updates, not the screen.
      await tester.pumpWidget(_card(fetched: OrderStatus.preparing));
      await tester.pumpAndSettle();

      expect(find.text('Your food is being prepared'), findsOneWidget);
    });

    testWidgets('a delivered order stops promising an arrival time', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _card(fetched: OrderStatus.outForDelivery, live: OrderStatus.delivered),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivered. Enjoy!'), findsOneWidget);
      expect(find.textContaining('Arriving by'), findsNothing);
    });

    testWidgets('an order on its way names the rider carrying it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _card(
          fetched: OrderStatus.outForDelivery,
          rider: const OrderRider(
            name: 'Ravi Kumar',
            phone: '9876500011',
            vehicle: 'scooter',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('9876500011'), findsOneWidget);
      expect(find.text('On a scooter'), findsOneWidget);
      // Two scooter icons now: the headline's, and the rider strip's.
      expect(find.byIcon(Icons.delivery_dining_rounded), findsNWidgets(2));
    });

    testWidgets('an order nobody has picked up renders exactly as it did', (
      WidgetTester tester,
    ) async {
      // The strip appears when there is someone to name and not before: no
      // placeholder, no "finding a rider", no reserved hole in the card.
      await tester.pumpWidget(_card(fetched: OrderStatus.outForDelivery));
      await tester.pumpAndSettle();

      expect(find.text('On its way to you'), findsOneWidget);
      // One icon, the headline's — the strip that would have added a second
      // one is simply not there.
      expect(find.byIcon(Icons.delivery_dining_rounded), findsOneWidget);
    });

    testWidgets('the rider is not named before the order leaves the kitchen', (
      WidgetTester tester,
    ) async {
      // Even with a rider to hand, a card showing a courier while the food is
      // still in the pan is a card describing the wrong minute.
      await tester.pumpWidget(
        _card(
          fetched: OrderStatus.preparing,
          rider: const OrderRider(
            name: 'Ravi Kumar',
            phone: '9876500011',
            vehicle: 'bike',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ravi Kumar'), findsNothing);
      expect(find.text('9876500011'), findsNothing);
    });

    testWidgets('a cancelled order is not a timeline with a gap in it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _card(fetched: OrderStatus.preparing, live: OrderStatus.cancelled),
      );
      await tester.pumpAndSettle();

      expect(find.text('This order was cancelled'), findsOneWidget);
      // No journey: it left. Drawing four grey dots and a stalled one would
      // suggest it is still coming.
      expect(find.text('Out for delivery'), findsNothing);
      expect(find.textContaining('Arriving by'), findsNothing);
    });
  });

  group('OrderStatus.journey', () {
    // Six since Phase 2 added `ready_for_pickup`; this assertion still said
    // five and had been red ever since.
    test('is the six stages an order that goes well passes through', () {
      expect(OrderStatus.journey, hasLength(6));
      expect(OrderStatus.journey.contains(OrderStatus.cancelled), isFalse);
      expect(OrderStatus.placed.step, 0);
      expect(OrderStatus.delivered.step, 5);
      // Cancelled has no place on the timeline, and `step` says so rather than
      // quietly returning 0 and lighting up "Placed".
      expect(OrderStatus.cancelled.step, -1);
    });
  });
}
