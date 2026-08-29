import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';

/// "Add a drink?" — the bottled drinks a kitchen sells, offered at the moment
/// somebody puts food in the cart, and again on the cart screen.
///
/// **A drink is a menu item here, not an add-on.** The `menu_option_groups`
/// route (0048) was the other candidate and is the wrong shape: an option has no
/// image, it folds into its dish's line so two curries would force two Cokes,
/// and `dish_options_sheet` opens for any dish that has a group — attaching one
/// to every dish would put a modal in front of every ADD button in the app.
/// These are real rows (migration 0140) with their own photo, their own price
/// and their own count.

/// The restaurant's bottled drinks, from the menu it has already fetched.
///
/// Derived from [menuProvider] rather than querying for itself: the menu is
/// disk-cached for two minutes and the drinks are a section of it, so the strip
/// costs nothing on a screen that has already loaded the menu and one cached
/// read on one that has not.
///
/// Matches the section by name because that is what migration 0140 wrote and
/// what the two kitchens with a pre-existing "Beverages" section already called
/// it. A kitchen whose drinks live under "Cold Beverages" or "Shakes &
/// Beverages" keeps those as menu sections and is not offered here — those are
/// made to order, and this strip is for the thing that comes out of a fridge.
final AutoDisposeFutureProviderFamily<List<MenuItem>, String> beveragesProvider =
    FutureProvider.autoDispose.family<List<MenuItem>, String>((
      Ref ref,
      String restaurantId,
    ) async {
      final List<MenuCategory> menu = await ref.watch(
        menuProvider(restaurantId).future,
      );
      for (final MenuCategory c in menu) {
        if (c.title == 'Beverages') return c.items;
      }
      return const <MenuItem>[];
    });

/// Whether [cart] already holds one of [beverages].
///
/// The one thing that stops the prompt being a nag: somebody who has already
/// picked a drink is not asked again.
bool cartHasABeverage(Cart cart, List<MenuItem> beverages) {
  final Set<String> ids = beverages.map((MenuItem b) => b.id).toSet();
  return cart.lines.any((CartLine l) => ids.contains(l.item.id));
}

/// Whether the drinks sheet has already been raised for the cart as it stands.
///
/// One offer per basket, not one per tap. Tapping CART, backing out and tapping
/// it again is the same customer answering the same question, and asking twice
/// is how a suggestion becomes a nag.
///
/// Resets itself when the basket becomes a different basket — emptied, or moved
/// to another kitchen. Done by watching those two facts rather than by having
/// `CartNotifier` reach out and clear a flag: the cart is domain state and
/// should not have to know that a widget somewhere counts its own prompts.
final NotifierProvider<BeverageOfferNotifier, bool> beverageOfferShownProvider =
    NotifierProvider<BeverageOfferNotifier, bool>(BeverageOfferNotifier.new);

class BeverageOfferNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Watched, not read. A change to either field rebuilds this notifier, which
    // is exactly the reset — a new kitchen or an emptied cart gets asked once
    // more, and adding a second dish to the same basket does not.
    ref.watch(
      cartProvider.select((Cart c) => (c.restaurantId, c.isEmpty)),
    );
    return false;
  }

  void markShown() => state = true;
}

/// Offer a drink alongside what is already in the cart.
///
/// Raised from two places since the sheet stopped firing on every add: opening a
/// dish, and tapping CART. [onceOnly] is what the CART button passes — it is the
/// trigger the customer hits repeatedly, so it asks once per basket and then
/// stays quiet.
///
/// Silent — and deliberately so — when the kitchen sells no bottled drink, when
/// there is already a drink in the cart, or when the cart is empty. That last
/// one is the point of the whole change: a drink is something to add *to* an
/// order, so there is nothing to offer against an empty basket.
Future<void> offerABeverage(
  BuildContext context,
  WidgetRef ref, {
  required String restaurantId,
  required String restaurantName,
  bool onceOnly = false,
}) async {
  // An empty cart is not a meal to drink with. Checked before the menu read, so
  // the common case costs nothing at all.
  if (ref.read(cartProvider).isEmpty) return;
  if (onceOnly && ref.read(beverageOfferShownProvider)) return;

  final List<MenuItem> beverages = await ref
      .read(beveragesProvider(restaurantId).future)
      // A drink is a nicety. If the menu read fails there is nothing to show and
      // nothing to say about it — the dish is already in the cart.
      .catchError((_) => const <MenuItem>[]);

  if (beverages.isEmpty) return;
  // The "you just added a drink" guard went with `justAdded`. It was there for
  // the old trigger, which fired on the add itself; the only caller now is the
  // CART button, and the check below already covers the case it protected — a
  // drink just added is a drink in the cart.
  if (cartHasABeverage(ref.read(cartProvider), beverages)) return;
  if (!context.mounted) return;

  if (onceOnly) ref.read(beverageOfferShownProvider.notifier).markShown();

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.pageGutter,
            ),
            child: Text(
              'Add a drink?',
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          BeverageRail(
            restaurantId: restaurantId,
            restaurantName: restaurantName,
          ),
        ],
      ),
    ),
  );
}

/// The horizontal strip of drinks. Renders nothing at all — not a heading, not
/// an empty box — for a kitchen that sells none, so it is safe to drop onto any
/// screen unconditionally.
class BeverageRail extends ConsumerWidget {
  const BeverageRail({
    required this.restaurantId,
    required this.restaurantName,
    this.heading,
    super.key,
  });

  final String restaurantId;
  final String restaurantName;

  /// A heading drawn above the strip. The sheet supplies its own title, so it
  /// passes none.
  final String? heading;

  /// Tall enough for the art, two lines of name and the ADD control, which is
  /// the whole card — a horizontal `ListView` needs the number up front.
  static const double _railHeight = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MenuItem> beverages =
        ref.watch(beveragesProvider(restaurantId)).value ?? const <MenuItem>[];
    if (beverages.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (heading != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.sm,
              ZopiqSpacing.pageGutter,
              0,
            ),
            child: Text(
              heading!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        SizedBox(
          height: _railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.pageGutter,
              vertical: ZopiqSpacing.sm,
            ),
            itemCount: beverages.length,
            separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
            itemBuilder: (BuildContext context, int i) => _BeverageCard(
              item: beverages[i],
              restaurantId: restaurantId,
              restaurantName: restaurantName,
            ),
          ),
        ),
      ],
    );
  }
}

class _BeverageCard extends ConsumerWidget {
  const _BeverageCard({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;

  static const double _width = 118;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int quantity = ref.watch(
      cartProvider.select((Cart c) => c.quantityOf(item.id)),
    );

    // The name is the whole name again. 0140 wrote these as `Brand (size)`
    // because it seeded a row per size, and this card used to split the size off
    // the end so "Coca Cola (750 ml)" did not wrap to "Coca Cola (750" / "ml)"
    // at 118pt. Migration 0147 collapsed the two rows into one card with a Size
    // option group, so there is no size in the name to lift out — a kitchen's
    // own "Bisleri (1 L)" would now keep its brackets, which is what a name
    // that genuinely contains a size should do.
    final String title = item.name;

    // "from ₹30", because ₹30 is the small and the sheet below can add to it.
    // A bare ₹30 over a card whose ADD button charges ₹50 is the kind of small
    // lie that gets read as a bug at the bill.
    final String price = item.isCustomizable
        ? 'from ₹${item.price}'
        : '₹${item.price}';

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: ZopiqRadii.rSm,
            child: SizedBox(
              // Square, matching the square every image is padded into on
              // upload (`c_pad,w_800,h_800`). A bottle is tall and the art is
              // letterboxed white around it, so a landscape box here would crop
              // that padding off and take the cap and the base with it.
              height: _width,
              width: _width,
              child: item.imageUrl.isEmpty
                  ? GradientImagePlaceholder(
                      seed: item.id,
                      icon: Icons.local_drink_rounded,
                      iconSize: 28,
                    )
                  : Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => GradientImagePlaceholder(
                        seed: item.id,
                        icon: Icons.local_drink_rounded,
                        iconSize: 28,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            title,
            maxLines: 1,
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
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: zc.textStrong,
                ),
              ),
              const Spacer(),
              AddToCartControl(
                width: 62,
                quantity: quantity,
                // Through `addDishToCart`, not `cart.add`, so ADD asks the size.
                //
                // This card used to add straight to the cart, which was right
                // while each size was its own row and the card already named
                // one. After 0147 a drink is one card carrying a required Size
                // group, and adding straight would silently take the 250 ml
                // every time — the customer would have no way to buy the large
                // at all.
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
