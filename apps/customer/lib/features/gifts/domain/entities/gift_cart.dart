import 'package:flutter/foundation.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';

/// One line in the gift bag: an item and how many of it.
///
/// Simpler than [CartLine] on the food side, and the difference is real rather
/// than an omission: a dish has options that change its price and therefore its
/// identity, so the same dish twice can be two lines. A gift has no options, so
/// an item id *is* the line id.
@immutable
class GiftCartLine {
  const GiftCartLine({required this.item, required this.quantity});

  final GiftItem item;
  final int quantity;

  int get lineTotal => item.price * quantity;

  GiftCartLine copyWith({int? quantity}) =>
      GiftCartLine(item: item, quantity: quantity ?? this.quantity);
}

/// What the customer is about to buy from one gift shop.
///
/// **Its own cart, not a mode of the food one.** Two reasons, and the second is
/// the one that settles it:
///
///   • [Cart] is typed to `MenuItem` all the way down — lines, options, the
///     bill, `place_order`'s payload. A gift is not a menu item and pretending
///     otherwise would mean a fake dish with a fake GST slab.
///   • A gift order and a food order are fulfilled by different people, arrive
///     by different means and settle differently. One cart holding both would
///     have to split at checkout anyway, and a cart that silently becomes two
///     orders is a cart nobody can reason about.
///
/// **One shop at a time**, for the same reason the food cart is one restaurant
/// at a time: an order is placed against a seller. Adding from a second shop
/// asks first — [isFromAnotherShop] is how the sheet knows to ask.
@immutable
class GiftCart {
  const GiftCart({
    this.shopId = '',
    this.shopName = '',
    this.lines = const <GiftCartLine>[],
  });

  static const GiftCart empty = GiftCart();

  final String shopId;
  final String shopName;
  final List<GiftCartLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  int get itemCount =>
      lines.fold(0, (int sum, GiftCartLine l) => sum + l.quantity);

  /// The bag's own arithmetic: items only. Tax is the server's to add — the
  /// receipt from `place_gift_order` is the truth, and a number computed here
  /// would only ever be an estimate of it (0096).
  int get subtotal =>
      lines.fold(0, (int sum, GiftCartLine l) => sum + l.lineTotal);

  int quantityOf(String itemId) => lines
      .where((GiftCartLine l) => l.item.id == itemId)
      .fold(0, (int sum, GiftCartLine l) => sum + l.quantity);

  /// Whether adding [item] would mean abandoning what is already in the bag.
  bool isFromAnotherShop(GiftItem item) =>
      isNotEmpty && item.shopId != shopId;

  /// The payload `place_gift_order` takes: ids and quantities, no prices. A
  /// client that could quote a total could get one wrong on purpose.
  List<Map<String, dynamic>> toOrderItems() => <Map<String, dynamic>>[
    for (final GiftCartLine l in lines)
      <String, dynamic>{'gift_item_id': l.item.id, 'quantity': l.quantity},
  ];

  GiftCart copyWith({
    String? shopId,
    String? shopName,
    List<GiftCartLine>? lines,
  }) => GiftCart(
    shopId: shopId ?? this.shopId,
    shopName: shopName ?? this.shopName,
    lines: lines ?? this.lines,
  );
}
