import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_mock_datasource.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_detail_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/orders_page.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_tracking_card.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

import '../../support/fake_auth_datasource.dart';
import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const AuthUser _user = AuthUser(
  id: 'usr_1',
  email: 'diner@example.com',
  phone: '+919876543210',
);

const Address _address = Address(
  id: 'home',
  label: 'Home',
  line1: 'Banjara Hills',
  city: 'Hyderabad',
  latitude: 17.4126,
  longitude: 78.4482,
);

/// Two dishes off the *mock menu* for `r1` — ids the reorder path can resolve.
/// Subtotal 580 → free delivery (≥ ₹500) + ₹29 tax = ₹609.
const Cart _seededCart = Cart(
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  lines: <CartLine>[
    CartLine(
      item: MenuItem(
        id: 'r1-m1',
        name: 'Signature Chicken Biryani',
        description: '',
        price: 320,
        isVeg: false,
      ),
      quantity: 1,
    ),
    CartLine(
      item: MenuItem(
        id: 'r1-m2',
        name: 'Paneer Butter Masala',
        description: '',
        price: 260,
        isVeg: true,
      ),
      quantity: 1,
    ),
  ],
);

class _SeededCartNotifier extends CartNotifier {
  @override
  Cart build() => _seededCart;
}

List<Override> _overrides({required bool seedCart}) => <Override>[
  ...storageOverrides(
    authState: const AuthSignedIn(_user),
    authDataSource: FakeAuthDataSource(signedInAs: _user),
    keyValueStore: FakeKeyValueStore(<String, String>{
      'zopiq.location.selected_address': jsonEncode(_address.toJson()),
    }),
  ),
  restaurantDataSourceProvider.overrideWithValue(
    const RestaurantMockDataSource(latency: _latency),
  ),
  menuDataSourceProvider.overrideWithValue(
    const MenuMockDataSource(latency: _latency),
  ),
  orderDataSourceProvider.overrideWithValue(
    OrderMockDataSource(latency: _latency),
  ),
  if (seedCart) cartProvider.overrideWith(_SeededCartNotifier.new),
];

Widget _app({bool seedCart = true}) => ProviderScope(
  overrides: _overrides(seedCart: seedCart),
  child: const ZopiqApp(),
);

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Home → profile → "My orders".
Future<void> _openOrders(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byIcon(Icons.person_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('My orders'));
  await tester.pumpAndSettle();
  expect(find.byType(OrdersPage), findsOneWidget);
}

/// Cart tab → checkout → place a COD order → back to Home.
Future<void> _placeCodOrder(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('Cart'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Proceed to checkout'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Place order · ₹609'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Back to home'));
  await tester.pumpAndSettle();
}

/// A past order, priced as it was charged. `unitPrice` is deliberately stale —
/// ₹999 for a dish that costs ₹320 today — so a reorder that reuses the
/// receipt's prices instead of the menu's is visible in the assertion.
CustomerOrder _pastOrder({List<OrderLine>? lines}) => CustomerOrder(
  id: 'ZPQ-1042',
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  status: OrderStatus.delivered,
  placedAt: DateTime(2026, 7, 12, 19, 42),
  deliveryTo: 'Banjara Hills, Hyderabad',
  etaMinutes: 30,
  paymentMethod: PaymentMethod.cod,
  subtotal: 580,
  deliveryFee: 0,
  taxes: 29,
  discount: 0,
  total: 609,
  lines:
      lines ??
      const <OrderLine>[
        OrderLine(
          menuItemId: 'r1-m1',
          name: 'Signature Chicken Biryani',
          unitPrice: 999,
          quantity: 2,
          lineTotal: 1998,
        ),
      ],
);

void main() {
  group('order history', () {
    testWidgets('an order the customer placed shows up in Your orders', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app());

      await _placeCodOrder(tester);
      await _openOrders(tester);

      expect(find.textContaining('ZPQ-'), findsOneWidget);
      expect(find.text('Test Kitchen'), findsOneWidget);
      expect(find.text('₹609'), findsOneWidget);
      // The card lists what was ordered rather than counting it — it used to
      // read "· 2 items". Naming the dishes is the stronger assertion anyway:
      // a count of two would pass even if the wrong two arrived.
      expect(
        find.text('1 × Signature Chicken Biryani, 1 × Paneer Butter Masala'),
        findsOneWidget,
      );
      expect(find.text('Placed'), findsOneWidget);
    });

    testWidgets('a customer who has never ordered is told so, not shown an '
        'error', (WidgetTester tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app(seedCart: false));

      await _openOrders(tester);

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Browse restaurants'), findsOneWidget);
    });

    testWidgets('opening an order shows the bill that was actually charged', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app());

      await _placeCodOrder(tester);
      await _openOrders(tester);
      await tester.tap(find.text('Test Kitchen'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailPage), findsOneWidget);
      expect(find.text('Item total'), findsOneWidget);
      expect(find.text('₹580'), findsOneWidget);
      // ₹0 delivery is something the customer was *given*, not something that
      // failed to happen.
      expect(find.text('FREE'), findsOneWidget);
      // Not "Total paid": the order was placed a moment ago, it is cash on
      // delivery, and nobody has paid anybody yet.
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
    });

    testWidgets('an order still on its way is tracked, not receipted', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app());

      await _placeCodOrder(tester);
      await _openOrders(tester);
      await tester.tap(find.text('Test Kitchen'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingCard), findsOneWidget);
      expect(
        find.text('Waiting for the restaurant to accept'),
        findsOneWidget,
      );
      expect(find.textContaining('Arriving by'), findsOneWidget);
      // The whole journey is drawn, not just the step it is on — the customer
      // wants to know what is left, not only where it is.
      expect(find.text('Out for delivery'), findsOneWidget);
      // The address is a promise, not a fact, until the food is there.
      expect(find.textContaining('Delivering to'), findsOneWidget);
      // The live card owns the status. A chip beside it would be a second,
      // staler copy of the same fact.
      expect(find.byType(OrderStatusChip), findsNothing);
    });

    testWidgets('a delivered order shows the receipt, not a timeline', (
      WidgetTester tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ..._overrides(seedCart: false),
            // A delivered order — the state the mock's own history can never
            // reach, because nothing in it plays the kitchen.
            orderByIdProvider(
              'ZPQ-1042',
            ).overrideWith((Ref ref) async => _pastOrder()),
          ],
          child: MaterialApp(
            theme: ZopiqTheme.light,
            home: const OrderDetailPage(orderId: 'ZPQ-1042'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingCard), findsNothing);
      expect(find.byType(OrderStatusChip), findsOneWidget);
      expect(find.text('Total paid'), findsOneWidget);
      expect(find.textContaining('Delivered to'), findsOneWidget);
    });
  });

  group('reorder', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: _overrides(seedCart: false));
      addTearDown(container.dispose);
    });

    test('rebuilds the cart from the order, priced at today\'s menu', () async {
      final ReorderOutcome outcome = await container
          .read(reorderControllerProvider.notifier)
          .reorder(_pastOrder());

      expect(outcome.added, 1);
      expect(outcome.unavailable, 0);

      final Cart cart = container.read(cartProvider);
      expect(cart.restaurantId, 'r1');
      expect(cart.lines.single.quantity, 2);
      // The receipt said ₹999. The menu says ₹320, and the menu is what the
      // customer is about to be charged.
      expect(cart.lines.single.item.price, 320);
      expect(cart.subtotal, 640);
    });

    test('loads what is still available and counts what is not', () async {
      final ReorderOutcome outcome = await container
          .read(reorderControllerProvider.notifier)
          .reorder(
            _pastOrder(
              lines: const <OrderLine>[
                OrderLine(
                  menuItemId: 'r1-m1',
                  name: 'Signature Chicken Biryani',
                  unitPrice: 320,
                  quantity: 1,
                  lineTotal: 320,
                ),
                OrderLine(
                  menuItemId: 'r1-delisted',
                  name: 'Discontinued Thali',
                  unitPrice: 200,
                  quantity: 1,
                  lineTotal: 200,
                ),
              ],
            ),
          );

      expect(outcome.added, 1);
      expect(outcome.unavailable, 1);
      expect(container.read(cartProvider).lines.single.item.id, 'r1-m1');
    });

    test('an order with nothing left on the menu leaves the cart alone', () async {
      // A cart the customer built by hand, which a failed reorder must not eat.
      container.read(cartProvider.notifier).replaceWith(
        restaurantId: 'r2',
        restaurantName: 'Somewhere Else',
        lines: _seededCart.lines,
      );

      final ReorderOutcome outcome = await container
          .read(reorderControllerProvider.notifier)
          .reorder(
            _pastOrder(
              lines: const <OrderLine>[
                OrderLine(
                  menuItemId: 'r1-gone',
                  name: 'Discontinued Thali',
                  unitPrice: 200,
                  quantity: 1,
                  lineTotal: 200,
                ),
              ],
            ),
          );

      expect(outcome.isEmpty, isTrue);
      expect(outcome.unavailable, 1);
      expect(container.read(cartProvider).restaurantId, 'r2');
      expect(container.read(cartProvider).lines.length, 2);
    });
  });
}
