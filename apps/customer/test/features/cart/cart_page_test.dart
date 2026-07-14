import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/app/zopiq_app.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/home/data/datasources/restaurant_mock_datasource.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

import '../../support/fake_stores.dart';

const Duration _latency = Duration(milliseconds: 10);

MenuItem _dish(String id, String name, int price) => MenuItem(
  id: id,
  name: name,
  description: '',
  price: price,
  isVeg: true,
);

/// ₹380 subtotal: under the ₹500 free-delivery line, so the progress bar and the
/// "add more" nudge are both live.
Cart _cart({int quantity = 1}) => Cart(
  restaurantId: 'r1',
  restaurantName: 'Test Kitchen',
  lines: <CartLine>[
    CartLine(item: _dish('r1-m1', 'Paneer Butter Masala', 260), quantity: quantity),
    CartLine(item: _dish('r1-m2', 'Butter Naan', 120), quantity: 1),
  ],
);

class _SeededCart extends CartNotifier {
  _SeededCart(this._initial);

  final Cart _initial;

  @override
  Cart build() => _initial;
}

ProviderContainer _container(Cart cart) => ProviderContainer(
  overrides: <Override>[
    ...storageOverrides(),
    restaurantDataSourceProvider.overrideWithValue(
      const RestaurantMockDataSource(latency: _latency),
    ),
    cartProvider.overrideWith(() => _SeededCart(cart)),
  ],
);

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Home → Cart tab.
Future<void> _openCart(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.widgetWithText(GestureDetector, 'Cart'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bill shows how far the cart is from free delivery', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    final ProviderContainer container = _container(_cart());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZopiqApp()),
    );
    await _openCart(tester);

    // ₹380 subtotal → ₹120 short of the ₹500 line, and a bar showing it.
    expect(find.text('Add ₹120 more for free delivery'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Nothing saved yet, so nothing claims otherwise.
    expect(find.textContaining('You saved'), findsNothing);
  });

  testWidgets('crossing the free-delivery line strikes out the fee and says '
      'what was saved', (WidgetTester tester) async {
    _useTallSurface(tester);
    // 2 × ₹260 + ₹120 = ₹640, over the line.
    final ProviderContainer container = _container(_cart(quantity: 2));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZopiqApp()),
    );
    await _openCart(tester);

    expect(find.text('FREE'), findsOneWidget);
    // The ₹40 they are not paying, struck through — being told you got
    // something is not the same as being shown what it was worth.
    expect(find.text('₹40'), findsOneWidget);
    expect(find.text('You saved ₹40 on this order'), findsOneWidget);
    expect(find.textContaining('more for free delivery'), findsNothing);
  });

  testWidgets('swiping a line away removes it, and Undo puts it back', (
    WidgetTester tester,
  ) async {
    _useTallSurface(tester);
    final ProviderContainer container = _container(_cart());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZopiqApp()),
    );
    await _openCart(tester);

    expect(find.text('Butter Naan'), findsOneWidget);

    await tester.drag(find.text('Butter Naan'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Butter Naan'), findsNothing);
    expect(container.read(cartProvider).lines, hasLength(1));

    // A swipe is easy to do by accident, so the way back is one tap.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider).lines, hasLength(2));
    expect(find.text('Butter Naan'), findsOneWidget);
  });

  testWidgets('undoing the last line restores the cart\'s restaurant, not an '
      'orphan cart', (WidgetTester tester) async {
    _useTallSurface(tester);
    final ProviderContainer container = _container(
      Cart(
        restaurantId: 'r1',
        restaurantName: 'Test Kitchen',
        lines: <CartLine>[
          CartLine(item: _dish('r1-m1', 'Paneer Butter Masala', 260), quantity: 1),
        ],
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZopiqApp()),
    );
    await _openCart(tester);

    await tester.drag(find.text('Paneer Butter Masala'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Removing the only line empties the cart — and an empty cart has no
    // restaurant. Undo has to bring it back, or checkout would be handed food
    // from nobody.
    expect(container.read(cartProvider).isEmpty, isTrue);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final Cart restored = container.read(cartProvider);
    expect(restored.lines, hasLength(1));
    expect(restored.restaurantId, 'r1');
    expect(restored.restaurantName, 'Test Kitchen');
  });

  testWidgets('emptying the cart asks first', (WidgetTester tester) async {
    _useTallSurface(tester);
    final ProviderContainer container = _container(_cart());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZopiqApp()),
    );
    await _openCart(tester);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Empty your cart?'), findsOneWidget);

    // Backing out of the dialog must not empty a cart the customer spent five
    // minutes building.
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(container.read(cartProvider).lines, hasLength(2));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty cart'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
  });
}
