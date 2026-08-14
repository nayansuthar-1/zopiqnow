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

  test('charges the flat delivery fee on a small basket', () {
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 200), quantity: 1),
    ]));

    expect(bill.deliveryFee, 40);
    expect(bill.taxes, 10); // 5% of 200
    expect(bill.total, 250); // 200 + 40 + 10
  });

  // Was 'waives delivery exactly at the threshold', asserting a ₹0 fee at ₹500.
  // Migration 0123 withdrew the threshold from `place_order` and
  // `checkout_preflight`, and `CartBill` mirrors them — so the same basket that
  // used to prove the waiver now proves there is no waiver left to apply.
  test('charges the flat delivery fee on a large basket too', () {
    final CartBill bill = CartBill.of(_cartOf(<CartLine>[
      CartLine(item: _item('a', 500), quantity: 1),
    ]));

    expect(bill.deliveryFee, 40);
    expect(bill.total, 565); // 500 + 40 + 25
  });

  test('subtracts a coupon discount from the total, not the subtotal', () {
    final CartBill bill = CartBill.of(
      _cartOf(<CartLine>[CartLine(item: _item('a', 400), quantity: 1)]),
      discount: 50,
    );

    expect(bill.subtotal, 400); // discount never rewrites the item total
    expect(bill.discount, 50);
    // 400 + 40 + 18 − 50. The tax is 5% of 350, not of 400: the coupon comes
    // off before GST is charged, because the taxable value is what the customer
    // actually pays (migration 0078, audit BIZ-005).
    expect(bill.taxes, 18);
    expect(bill.total, 408);
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
