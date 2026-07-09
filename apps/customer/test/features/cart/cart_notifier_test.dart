import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

MenuItem _item(String id, {int price = 100}) => MenuItem(
      id: id,
      name: 'Dish $id',
      description: '',
      price: price,
      isVeg: true,
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  CartNotifier notifier() => container.read(cartProvider.notifier);
  Cart cart() => container.read(cartProvider);

  test('starts empty', () {
    expect(cart().isEmpty, isTrue);
    expect(cart().itemCount, 0);
    expect(cart().restaurantId, isNull);
  });

  test('adding an item records the restaurant and the line', () {
    final AddToCartResult result = notifier().add(
      restaurantId: 'r1',
      restaurantName: 'Paradise',
      item: _item('a'),
    );

    expect(result, AddToCartResult.added);
    expect(cart().restaurantId, 'r1');
    expect(cart().restaurantName, 'Paradise');
    expect(cart().quantityOf('a'), 1);
    expect(cart().subtotal, 100);
  });

  test('adding the same item again increments rather than duplicating', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));

    expect(cart().lines.length, 1);
    expect(cart().quantityOf('a'), 2);
    expect(cart().itemCount, 2);
  });

  test('adding from another restaurant is refused, leaving the cart intact', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));

    final AddToCartResult result = notifier().add(
      restaurantId: 'r2',
      restaurantName: 'Green Theory',
      item: _item('b'),
    );

    expect(result, AddToCartResult.differentRestaurant);
    expect(cart().restaurantId, 'r1');
    expect(cart().quantityOf('b'), 0);
    expect(cart().lines.length, 1);
  });

  test('startNewCartWith replaces the cart wholesale', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().startNewCartWith(
      restaurantId: 'r2',
      restaurantName: 'Green Theory',
      item: _item('b', price: 250),
    );

    expect(cart().restaurantId, 'r2');
    expect(cart().lines.length, 1);
    expect(cart().quantityOf('a'), 0);
    expect(cart().quantityOf('b'), 1);
    expect(cart().subtotal, 250);
  });

  test('decrementing to zero drops the line and empties the cart', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().decrement('a');

    expect(cart().isEmpty, isTrue);
    // The restaurant binding must clear too, or the next add from a *different*
    // restaurant would be wrongly refused.
    expect(cart().restaurantId, isNull);
  });

  test('decrementing an absent item is a no-op', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().decrement('ghost');

    expect(cart().quantityOf('a'), 1);
    expect(cart().lines.length, 1);
  });

  test('removeLine drops one line but keeps the rest', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('b'));
    notifier().removeLine('a');

    expect(cart().quantityOf('a'), 0);
    expect(cart().quantityOf('b'), 1);
    expect(cart().restaurantId, 'r1');
  });

  test('clear resets to an empty cart', () {
    notifier().add(restaurantId: 'r1', restaurantName: 'Paradise', item: _item('a'));
    notifier().clear();

    expect(cart().isEmpty, isTrue);
    expect(cart().restaurantId, isNull);
  });
}
