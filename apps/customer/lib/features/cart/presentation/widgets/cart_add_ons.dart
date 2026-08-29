import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';

/// What the cart offers to add — drinks and the kitchen's other small things.
///
/// Replaces both the "Add a drink" rail and the "Add more items" row that used
/// to sit at the bottom of the cart. Those were two controls answering one
/// question, and the drinks half of it was the wrong half on its own: somebody
/// looking at a finished order wants a drink *or* a side *or* a sweet, and being
/// shown only bottles makes the cart look like a fridge.
///
/// Ordered cheapest-first, because an add-on is by definition the smaller half
/// of the order — a second main course is not something to suggest at the bill.
/// Drinks are capped rather than excluded or promoted: they are ₹30 and
/// photographed, so an unweighted cheapest-first list is eight bottles, which is
/// the thing this widget exists not to be.
///
/// Anything already in the cart is dropped. Suggesting what somebody has just
/// added reads as the app not knowing what it is holding.
final AutoDisposeFutureProviderFamily<List<MenuItem>, String>
cartAddOnsProvider = FutureProvider.autoDispose.family<List<MenuItem>, String>((
  Ref ref,
  String restaurantId,
) async {
  final List<MenuCategory> menu = await ref.watch(
    menuProvider(restaurantId).future,
  );
  final Cart cart = ref.watch(cartProvider);
  final Set<String> inCart = cart.lines
      .map((CartLine l) => l.item.id)
      .toSet();

  final List<MenuItem> candidates =
      <MenuItem>[
          for (final MenuCategory c in menu)
            for (final MenuItem i in c.items)
              if (!inCart.contains(i.id)) i,
        ]
        ..sort((MenuItem a, MenuItem b) {
          final int byPrice = a.price.compareTo(b.price);
          // Ties broken by id so the rail does not reshuffle between rebuilds —
          // a strip of cards that reorders while somebody is reaching for one is
          // how a tap lands on the wrong thing.
          return byPrice != 0 ? byPrice : a.id.compareTo(b.id);
        });

  final List<MenuItem> shown = <MenuItem>[];
  int drinks = 0;
  for (final MenuItem c in candidates) {
    if (shown.length == _max) break;
    if (c.isBottledDrink) {
      if (drinks == _maxDrinks) continue;
      drinks++;
    }
    shown.add(c);
  }
  return shown;
});

/// Enough to swipe through without turning the cart into a second menu.
const int _max = 10;

/// How many of [_max] may be bottled drinks.
const int _maxDrinks = 4;

/// The strip itself, plus the way back to the full menu.
///
/// Renders nothing when there is nothing left to suggest — a cart holding the
/// kitchen's entire menu is not a real case, but a one-dish kitchen is, and a
/// heading over an empty rail is worse than no heading.
class CartAddOnRail extends ConsumerWidget {
  const CartAddOnRail({
    required this.restaurantId,
    required this.restaurantName,
    super.key,
  });

  final String restaurantId;
  final String restaurantName;

  static const double _railHeight = 196;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    final List<MenuItem> items =
        ref.watch(cartAddOnsProvider(restaurantId)).valueOrNull ??
        const <MenuItem>[];

    // The menu link stays even with nothing to suggest. Without it the only way
    // off a non-empty cart is the app-bar back arrow, which goes to Home — so a
    // customer who forgot something had to find the kitchen again from the feed.
    // That dead end is what the old "Add more items" row was for, and it is not
    // reintroduced by replacing the row with this.
    final Widget menuLink = InkWell(
      onTap: () => context.pushNamed(
        Routes.menu,
        pathParameters: <String, String>{'id': restaurantId},
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Row(
          children: <Widget>[
            Icon(Icons.restaurant_menu_rounded, size: 20, color: zc.primary),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Text(
                'See the full menu',
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: zc.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (items.isEmpty) return menuLink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZopiqSpacing.lg,
            ZopiqSpacing.lg,
            ZopiqSpacing.lg,
            0,
          ),
          child: Text(
            'Add to your order',
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: _railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.lg,
              vertical: ZopiqSpacing.md,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
            itemBuilder: (BuildContext context, int i) => _AddOnCard(
              item: items[i],
              restaurantId: restaurantId,
              restaurantName: restaurantName,
            ),
          ),
        ),
        menuLink,
      ],
    );
  }
}

class _AddOnCard extends ConsumerWidget {
  const _AddOnCard({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;

  static const double _width = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int quantity = ref.watch(
      cartProvider.select((Cart c) => c.quantityOf(item.id)),
    );

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: ZopiqRadii.rSm,
            child: SizedBox(
              // Square, matching the padding every packshot is uploaded into.
              // A bottle is tall and letterboxed white; a landscape box would
              // crop the cap and the base off.
              height: _width,
              width: _width,
              child: item.imageUrl.isEmpty
                  ? GradientImagePlaceholder(
                      seed: item.id,
                      icon: Icons.restaurant_rounded,
                      iconSize: 26,
                    )
                  : ZopiqNetworkImage(
                      url: item.imageUrl,
                      fallback: GradientImagePlaceholder(
                        seed: item.id,
                        icon: Icons.restaurant_rounded,
                        iconSize: 26,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: zc.textStrong,
            ),
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Text(
                // "from ₹30" when a size or an add-on can push it up, so the
                // number on the card is never less than what the ADD charges.
                item.isCustomizable ? 'from ₹${item.price}' : '₹${item.price}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: zc.textStrong,
                ),
              ),
              const Spacer(),
              AddToCartControl(
                width: 58,
                quantity: quantity,
                // Through the shared flow, so a dish with sizes asks for one
                // rather than silently taking the cheapest.
                onAdd: () => addDishToCart(
                  context,
                  ref,
                  item: item,
                  restaurantId: restaurantId,
                  restaurantName: restaurantName,
                ),
                onIncrement: () =>
                    ref.read(cartProvider.notifier).increment(item.id),
                onDecrement: () =>
                    ref.read(cartProvider.notifier).decrement(item.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
