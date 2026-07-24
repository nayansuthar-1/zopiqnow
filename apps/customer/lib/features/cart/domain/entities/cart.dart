import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

/// One line in the cart: a menu item, its chosen options, and a quantity.
///
/// The same dish with different options is a *different* line — a Full biryani
/// with cheese and a Half without are two rows, not one — so a line is
/// identified by [lineId], the dish plus its option set, not by the dish alone.
@immutable
class CartLine {
  const CartLine({
    required this.item,
    required this.quantity,
    this.options = const <MenuOption>[],
  });

  final MenuItem item;
  final int quantity;

  /// The options chosen for this line (empty for a plain dish). Priced by their
  /// deltas on top of the dish's base price.
  final List<MenuOption> options;

  /// The dish's base plus the chosen options — what one of this line costs.
  int get unitPrice =>
      item.price + options.fold(0, (int s, MenuOption o) => s + o.priceDelta);

  int get lineTotal => unitPrice * quantity;

  /// A stable identity for the dish-and-its-options. Two lines merge only when
  /// they are the exact same dish with the exact same options; option order does
  /// not matter, so the ids are sorted.
  String get lineId {
    if (options.isEmpty) return item.id;
    final List<String> ids = options.map((MenuOption o) => o.id).toList()
      ..sort();
    return '${item.id}#${ids.join('_')}';
  }

  /// The chosen options as a comma-joined line ("Full, Extra cheese"), or empty.
  String get optionsLabel => options.map((MenuOption o) => o.name).join(', ');

  CartLine copyWith({int? quantity}) => CartLine(
    item: item,
    quantity: quantity ?? this.quantity,
    options: options,
  );
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

  int get itemCount => lines.fold(0, (int sum, CartLine l) => sum + l.quantity);

  int get subtotal => lines.fold(0, (int sum, CartLine l) => sum + l.lineTotal);

  /// Total quantity of [menuItemId] across all its configurations (0 if absent)
  /// — a dish added Half once and Full twice reads as three.
  int quantityOf(String menuItemId) => lines
      .where((CartLine l) => l.item.id == menuItemId)
      .fold(0, (int sum, CartLine l) => sum + l.quantity);

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
