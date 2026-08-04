import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';

/// Outcome of an add attempt, so the sheet knows whether to ask first.
enum AddToGiftBagResult {
  /// Added, or the quantity went up.
  added,

  /// The bag holds items from another shop. The caller confirms, then calls
  /// [GiftCartNotifier.startNewBagWith].
  differentShop,
}

/// The gift bag. Its own notifier beside the food cart, never a mode of it —
/// see [GiftCart] for why the two cannot share a type.
///
/// **Deliberately not persisted**, unlike the food cart. That is not an
/// oversight and it is worth stating: a food cart survives a kill because
/// somebody assembling dinner gets interrupted and comes back in ten minutes. A
/// gift bag restored a week later is a bag of prices that have since moved and a
/// shop that may have closed — and the first thing it would do is fail at
/// checkout with "Something in your gift bag is no longer available." An empty
/// bag is a better welcome than a stale one. If gifts ever grow a wishlist, that
/// is the feature this would otherwise be pretending to be.
class GiftCartNotifier extends Notifier<GiftCart> {
  @override
  GiftCart build() => GiftCart.empty;

  /// Adds [item], or raises its quantity. Refuses across shops — the caller
  /// asks, then calls [startNewBagWith].
  AddToGiftBagResult add(GiftItem item, {int quantity = 1}) {
    if (state.isFromAnotherShop(item)) {
      return AddToGiftBagResult.differentShop;
    }

    final List<GiftCartLine> lines = <GiftCartLine>[...state.lines];
    final int at = lines.indexWhere((GiftCartLine l) => l.item.id == item.id);

    if (at >= 0) {
      // Capped at 20, which is what `place_gift_order` accepts. Refusing here
      // rather than at the server means the wall is where the finger is.
      final int next = (lines[at].quantity + quantity).clamp(1, 20);
      lines[at] = lines[at].copyWith(quantity: next);
    } else {
      lines.add(GiftCartLine(item: item, quantity: quantity.clamp(1, 20)));
    }

    state = state.copyWith(
      shopId: item.shopId,
      // Filled in by the shop page, which is the only screen that knows the
      // name. An empty one is harmless: the receipt's name comes from the
      // server, which reads it off the shop row.
      shopName: state.shopName,
      lines: lines,
    );
    return AddToGiftBagResult.added;
  }

  /// Throws the bag away and starts a new one at [item]'s shop.
  void startNewBagWith(GiftItem item, {int quantity = 1}) {
    state = GiftCart(
      shopId: item.shopId,
      lines: <GiftCartLine>[GiftCartLine(item: item, quantity: quantity.clamp(1, 20))],
    );
  }

  /// Records whose shop this is, so the bag can say so without a fetch.
  void nameShop(String shopId, String shopName) {
    if (state.shopId == shopId) state = state.copyWith(shopName: shopName);
  }

  void setQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      remove(itemId);
      return;
    }
    state = state.copyWith(
      lines: <GiftCartLine>[
        for (final GiftCartLine l in state.lines)
          if (l.item.id == itemId)
            l.copyWith(quantity: quantity.clamp(1, 20))
          else
            l,
      ],
    );
  }

  void remove(String itemId) {
    final List<GiftCartLine> lines = state.lines
        .where((GiftCartLine l) => l.item.id != itemId)
        .toList(growable: false);
    state = lines.isEmpty ? GiftCart.empty : state.copyWith(lines: lines);
  }

  void clear() => state = GiftCart.empty;
}

final NotifierProvider<GiftCartNotifier, GiftCart> giftCartProvider =
    NotifierProvider<GiftCartNotifier, GiftCart>(GiftCartNotifier.new);
