import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// One line in the cart: a menu item plus its quantity.
@immutable
class CartLine {
  const CartLine({required this.item, required this.quantity});

  final MenuItem item;
  final int quantity;

  int get lineTotal => item.price * quantity;

  CartLine copyWith({int? quantity}) =>
      CartLine(item: item, quantity: quantity ?? this.quantity);
}

/// The customer's cart. A cart belongs to a single restaurant (food-delivery
/// rule); adding from a different vendor requires starting a new cart.
@immutable
class Cart {
  const Cart({
    this.restaurantId,
    this.restaurantName,
    this.lines = const <CartLine>[],
  });

  const Cart.empty() : this();

  final String? restaurantId;
  final String? restaurantName;
  final List<CartLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  int get itemCount =>
      lines.fold(0, (int sum, CartLine l) => sum + l.quantity);

  int get subtotal =>
      lines.fold(0, (int sum, CartLine l) => sum + l.lineTotal);

  /// Current quantity of [menuItemId] in the cart (0 if absent).
  int quantityOf(String menuItemId) {
    for (final CartLine l in lines) {
      if (l.item.id == menuItemId) return l.quantity;
    }
    return 0;
  }

  Cart copyWith({
    String? restaurantId,
    String? restaurantName,
    List<CartLine>? lines,
  }) {
    return Cart(
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      lines: lines ?? this.lines,
    );
  }
}
