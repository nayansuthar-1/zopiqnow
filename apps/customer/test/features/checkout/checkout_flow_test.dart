import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/data/datasources/order_mock_datasource.dart';
import 'package:zopiqnow/features/checkout/presentation/gateways/mock_payment_gateway.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/checkout_page.dart';
import 'package:zopiqnow/features/checkout/presentation/pages/order_success_page.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

const AuthUser _user = AuthUser(id: 'usr_1', phone: '+919876543210');

const Address _address = Address(
  id: 'home',
  label: 'Home',
  line1: 'Banjara Hills',
  city: 'Hyderabad',
  latitude: 17.4126,
  longitude: 78.4482,
);

/// Two dishes, subtotal 400 → ₹40 delivery + ₹20 tax = ₹460 to pay.
const Cart _seededCart = Cart(
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  lines: <CartLine>[
    CartLine(
      item: MenuItem(
        id: 'a',
        name: 'Paneer Butter Masala',
        description: '',
        price: 250,
        isVeg: true,
      ),
      quantity: 1,
    ),
    CartLine(
      item: MenuItem(
        id: 'b',
        name: 'Butter Naan',
        description: '',
        price: 150,
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

Widget _app({bool withAddress = true}) {
  return ProviderScope(
    overrides: <Override>[
      ...storageOverrides(
        authState: const AuthSignedIn(_user),
        keyValueStore: FakeKeyValueStore(<String, String>{
          if (withAddress)
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
      paymentGatewayProvider.overrideWith(
        (Ref ref) => MockPaymentGateway(
          navigatorKey: ref.watch(rootNavigatorKeyProvider),
          latency: _latency,
        ),
      ),
      cartProvider.overrideWith(_SeededCartNotifier.new),
    ],
    child: const ZopiqApp(),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Reduce motion, as the OS setting would: Home's hero banner loops ambient
  // animations that would keep `pumpAndSettle` from ever settling.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Home feed → Cart tab → "Proceed to checkout".
Future<void> _openCheckout(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('Cart'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Proceed to checkout'));
  await tester.pumpAndSettle();
  expect(find.byType(CheckoutPage), findsOneWidget);
}

/// Selects UPI and taps the CTA, leaving the mock gateway's sheet open.
///
/// No `pumpAndSettle` while a payment is in flight: both CTAs spin an
/// indeterminate progress indicator, which never settles. Pump explicitly.
Future<void> _openPaymentSheet(WidgetTester tester) async {
  await tester.tap(find.text('UPI'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pay ₹460'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // Sheet slides in.
  expect(find.text('UPI payment'), findsOneWidget);
}

/// Runs out the gateway's latency, the sheet's exit, and order placement.
Future<void> _drainPayment(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50)); // Gateway settles.
  await tester.pump(const Duration(milliseconds: 400)); // Sheet slides out.
  await tester.pump(const Duration(milliseconds: 50)); // Order is placed.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('checkout shows the address, order recap, and live COD total', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);

    expect(find.text('Banjara Hills, Hyderabad'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('1 × Paneer Butter Masala'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('Place order · ₹460'), findsOneWidget);
  });

  testWidgets('placing a COD order reaches the confirmation and empties the '
      'cart', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);

    await tester.tap(find.text('Place order · ₹460'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(find.text('Order placed!'), findsOneWidget);
    expect(find.textContaining('ZPQ-'), findsOneWidget);
    expect(find.text('Pay ₹460 in cash on delivery'), findsOneWidget);

    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('a valid coupon discounts the bill and can be removed', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);

    await tester.enterText(find.byType(TextField), 'WELCOME50');
    await tester.tap(find.text('APPLY'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('WELCOME50 applied'), findsOneWidget);
    expect(find.text('Coupon discount'), findsOneWidget);
    expect(find.text('-₹50'), findsOneWidget);
    expect(find.text('Place order · ₹410'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove coupon'));
    await tester.pumpAndSettle();

    expect(find.text('Place order · ₹460'), findsOneWidget);
  });

  testWidgets('an unknown coupon shows the service\'s reason', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);

    await tester.enterText(find.byType(TextField), 'FREELUNCH');
    await tester.tap(find.text('APPLY'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('This code isn\'t valid.'), findsOneWidget);
    expect(find.text('Place order · ₹460'), findsOneWidget);
  });

  testWidgets('paying by UPI settles on the mock gateway and the receipt shows '
      'the payment reference', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);
    await _openPaymentSheet(tester);

    // The sheet's own CTA, above the checkout screen's.
    await tester.tap(find.text('Pay ₹460').last);
    await _drainPayment(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(find.textContaining('Paid ₹460 · pay_mock_'), findsOneWidget);
  });

  testWidgets('a declined UPI payment says so and places no order', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);
    await _openPaymentSheet(tester);

    await tester.tap(find.text('Simulate a failed payment'));
    await _drainPayment(tester);

    expect(find.byType(OrderSuccessPage), findsNothing);
    expect(find.byType(CheckoutPage), findsOneWidget);
    expect(
      find.text('Your payment was declined. Try another method.'),
      findsOneWidget,
    );
  });

  testWidgets('dismissing the payment sheet charges nothing and places no '
      'order', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app());
    await _openCheckout(tester);
    await _openPaymentSheet(tester);

    await tester.tap(find.byTooltip('Cancel payment'));
    await _drainPayment(tester);

    // No error either: they closed it, they know. Just back where they were.
    expect(find.byType(OrderSuccessPage), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Pay ₹460'), findsOneWidget);
  });

  testWidgets('with no delivery address, the CTA opens the address picker '
      'instead of placing an order', (WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(withAddress: false));
    await _openCheckout(tester);

    expect(find.text('No address selected'), findsOneWidget);

    await tester.tap(find.text('Select delivery address'));
    await tester.pumpAndSettle();

    // The saved-address sheet, not an order.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Work'), findsOneWidget);
  });
}
