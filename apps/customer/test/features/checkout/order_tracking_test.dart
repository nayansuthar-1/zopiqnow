import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
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
Widget _card({required OrderStatus fetched, OrderStatus? live}) => ProviderScope(
  overrides: <Override>[
    orderStatusProvider('ZPQ-1042').overrideWith(
      (Ref ref) => live == null
          ? const Stream<OrderStatus>.empty()
          : Stream<OrderStatus>.value(live),
    ),
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
    test('is the five stages an order that goes well passes through', () {
      expect(OrderStatus.journey, hasLength(5));
      expect(OrderStatus.journey.contains(OrderStatus.cancelled), isFalse);
      expect(OrderStatus.placed.step, 0);
      expect(OrderStatus.delivered.step, 4);
      // Cancelled has no place on the timeline, and `step` says so rather than
      // quietly returning 0 and lighting up "Placed".
      expect(OrderStatus.cancelled.step, -1);
    });
  });
}
