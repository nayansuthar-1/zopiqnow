import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';

/// Outcome of an add attempt, so the UI knows whether to prompt.
enum AddToCartResult {
  /// Item was added / incremented in the current cart.
  added,

  /// The cart holds items from another restaurant — caller should confirm
  /// starting a new cart, then call [CartNotifier.startNewCartWith].
  differentRestaurant,
}

/// The single source of truth for the cart. Updates are synchronous and
/// immediate (optimistic UI — Rule 2.6); persistence/sync to the backend is a
/// later concern behind this same API.
class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart.empty();

  AddToCartResult add({
    required String restaurantId,
    required String restaurantName,
    required MenuItem item,
  }) {
    if (state.isNotEmpty && state.restaurantId != restaurantId) {
      return AddToCartResult.differentRestaurant;
    }
    state = _withRestaurant(restaurantId, restaurantName)._upsert(item, 1);
    return AddToCartResult.added;
  }

  /// Clears the cart and adds [item] from the new restaurant (after the user
  /// confirms the "start a new cart" prompt).
  void startNewCartWith({
    required String restaurantId,
    required String restaurantName,
    required MenuItem item,
  }) {
    state = Cart(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
    )._upsert(item, 1);
  }

  /// Replaces the cart wholesale — the reorder path.
  ///
  /// Whatever was in the cart is dropped, because a cart belongs to one
  /// restaurant and reorder is not an "add". The caller is responsible for
  /// having asked first when the cart held someone else's food; [add] returns
  /// [AddToCartResult.differentRestaurant] for the same reason.
  void replaceWith({
    required String restaurantId,
    required String restaurantName,
    required List<CartLine> lines,
  }) {
    state = lines.isEmpty
        ? const Cart.empty()
        : Cart(
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            lines: lines,
          );
  }

  void increment(String menuItemId) {
    state = state._delta(menuItemId, 1);
  }

  void decrement(String menuItemId) {
    state = state._delta(menuItemId, -1);
  }

  void removeLine(String menuItemId) {
    final List<CartLine> lines = state.lines
        .where((CartLine l) => l.item.id != menuItemId)
        .toList(growable: false);
    state = lines.isEmpty ? const Cart.empty() : state.copyWith(lines: lines);
  }

  void clear() => state = const Cart.empty();

  Cart _withRestaurant(String id, String name) =>
      state.isEmpty ? Cart(restaurantId: id, restaurantName: name) : state;
}

extension _CartOps on Cart {
  /// Adds [delta] to an item's quantity, inserting the line if needed and
  /// dropping it (and emptying the cart) when quantity hits zero.
  Cart _upsert(MenuItem item, int delta) {
    final List<CartLine> next = <CartLine>[...lines];
    final int i = next.indexWhere((CartLine l) => l.item.id == item.id);
    if (i == -1) {
      if (delta <= 0) return this;
      next.add(CartLine(item: item, quantity: delta));
    } else {
      final int q = next[i].quantity + delta;
      if (q <= 0) {
        next.removeAt(i);
      } else {
        next[i] = next[i].copyWith(quantity: q);
      }
    }
    if (next.isEmpty) return const Cart.empty();
    return copyWith(lines: next);
  }

  /// Applies a quantity delta to an existing item id (no-op if absent).
  Cart _delta(String menuItemId, int delta) {
    final int i = lines.indexWhere((CartLine l) => l.item.id == menuItemId);
    if (i == -1) return this;
    return _upsert(lines[i].item, delta);
  }
}

final NotifierProvider<CartNotifier, Cart> cartProvider =
    NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
