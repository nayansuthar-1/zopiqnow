import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_options_sheet.dart';

/// Adding a dish to the cart, with everything that can interrupt it.
///
/// Two screens do this now — the menu row and the dish sheet it opens — and both
/// have to handle the same two interruptions in the same order: a customisable
/// dish asks its questions first, and a cart belonging to another restaurant has
/// to be emptied before this dish can go in. Neither is a detail of *where* the
/// customer tapped, which is why this is one function rather than a copy in each.
///
/// The "start a new cart" prompt lives here, at the moment of adding, rather than
/// on the cart screen — by the time somebody opens the cart, the decision has
/// already been made for them.
Future<void> addDishToCart(
  BuildContext context,
  WidgetRef ref, {
  required MenuItem item,
  required String restaurantId,
  required String restaurantName,
}) async {
  List<MenuOption> options = const <MenuOption>[];
  if (item.isCustomizable) {
    final List<MenuOption>? chosen = await showDishOptionsSheet(
      context,
      item: item,
    );
    if (chosen == null) return; // dismissed
    options = chosen;
  }
  if (!context.mounted) return;

  final CartNotifier cart = ref.read(cartProvider.notifier);
  final AddToCartResult result = cart.add(
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    item: item,
    options: options,
  );
  if (result == AddToCartResult.added) return;

  final String? existing = ref.read(cartProvider).restaurantName;
  final bool? replace = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Start a new cart?'),
      content: Text(
        'Your cart has items from $existing. Adding this dish will empty it.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep my cart'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Start new cart'),
        ),
      ],
    ),
  );

  if (replace ?? false) {
    cart.startNewCartWith(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      item: item,
      options: options,
    );
  }
}
