import 'package:flutter_test/flutter_test.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

MenuItem _item(String id, int price) => MenuItem(
      id: id,
      name: 'Dish $id',
      description: '',
      price: price,
      isVeg: true,
    );

Cart _cartOf(List<CartLine> lines) => Cart(
      restaurantId: 'r1',
      restaurantName: 'Test Kitchen',
      lines: lines,
    );

void main() {
  test('an empty cart bills nothing, not even a delivery fee', () {
    final CartBill bill = CartBill.of(const Cart.empty());

    expect(bill.subtotal, 0);
    expect(bill.deliveryFee, 0);
    expect(bill.taxes, 0);
    expect(bill.total, 0);
  });

  test('sums line totals across quantities', () {
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 100), quantity: 2),
      CartLine(item: _item('b', 50), quantity: 3),
    ]));

    expect(bill.subtotal, 350); // 200 + 150
  });

  test('charges the flat delivery fee below the free-delivery threshold', () {
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 200), quantity: 1),
    ]));

    expect(bill.deliveryFee, 40);
    expect(bill.hasFreeDelivery, isFalse);
    expect(bill.amountToFreeDelivery, 300);
    expect(bill.taxes, 10); // 5% of 200
    expect(bill.total, 250); // 200 + 40 + 10
  });

  test('waives delivery exactly at the threshold', () {
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 500), quantity: 1),
    ]));

    expect(bill.hasFreeDelivery, isTrue);
    expect(bill.deliveryFee, 0);
    expect(bill.amountToFreeDelivery, 0);
    expect(bill.total, 525); // 500 + 0 + 25
  });

  test('subtracts a coupon discount from the total, not the subtotal', () {
    final CartBill bill = CartBill.of(
      _cartOf(<CartLine>[CartLine(item: _item('a', 400), quantity: 1)]),
      discount: 50,
    );

    expect(bill.subtotal, 400); // discount never rewrites the item total
    expect(bill.discount, 50);
    expect(bill.total, 410); // 400 + 40 + 20 − 50
  });

  test('an empty cart ignores a discount', () {
    final CartBill bill = CartBill.of(const Cart.empty(), discount: 50);

    expect(bill.discount, 0);
    expect(bill.total, 0);
  });

  test('rounds fractional tax to the nearest rupee', () {
    // 5% of 199 = 9.95 → 10, not 9.
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 199), quantity: 1),
    ]));

    expect(bill.taxes, 10);
    expect(bill.total, 249); // 199 + 40 + 10
  });
}
