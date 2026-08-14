import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';

/// The whole dish, opened by tapping its row on the menu.
///
/// The row is a summary and has to stay one: it is 118pt of art beside two lines
/// of description, repeated a hundred times down a scrolling menu. Everything a
/// restaurant can say about a dish does not fit there and should not — the photo
/// is a thumbnail, the description is clipped at two lines, and a serving window
/// or a prep time has nowhere to go at all. This is where the rest of it lives.
///
/// **Eighty-two per cent of the screen.** It was 70, which was right when the
/// sheet ended at the description; it now carries a rail of other dishes from
/// the same kitchen, and 70 put that rail permanently below the fold where
/// nobody would ever meet it. A strip of the menu is still visible above, so the
/// sheet still reads as a closer look at a row that is still there rather than
/// as a page the customer has navigated to and must come back from.
void showDishDetailSheet(
  BuildContext context, {
  required MenuItem item,
  required String restaurantId,
  required String restaurantName,
  required bool enabled,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      // A fraction of the constraints the sheet is *given*, not of
      // `MediaQuery.size.height` — `useSafeArea` has already taken the status
      // bar and the gesture inset off those. Measuring against the raw screen
      // would ask for 82% of a taller box than exists and overflow by exactly
      // the notch on the phones that have one.
      heightFactor: 0.82,
      child: _DishDetailSheet(
        item: item,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        enabled: enabled,
      ),
    ),
  );
}

class _DishDetailSheet extends ConsumerWidget {
  const _DishDetailSheet({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
    required this.enabled,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int quantity = ref.watch(
      cartProvider.select((c) => c.quantityOf(item.id)),
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.pageGutter,
              0,
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.md,
            ),
            children: <Widget>[
              // The photo, with the Add control straddling its bottom edge.
              //
              // This is the Swiggy/Zomato dish shape and it is doing a job
              // beyond decoration: the control used to live in a bar at the very
              // bottom of the sheet, two screens away from the dish on anything
              // with a description, so the picture and the way to order it were
              // never visible at the same time. Sitting on the image it is next
              // to the thing it adds.
              Stack(
                // The control hangs 18pt below the image's bottom edge. Without
                // this it would be cut off at exactly the point that makes the
                // overlap read as a mistake.
                clipBehavior: Clip.none,
                children: <Widget>[
                  AspectRatio(
                    // Wider than the row's 118×96 thumbnail: at this size the
                    // photo is the point of the sheet rather than an identifier
                    // for a line of text.
                    aspectRatio: 16 / 10,
                    child: ClipRRect(
                      borderRadius: ZopiqRadii.rMd,
                      child: ZopiqNetworkImage(
                        url: item.imageUrl,
                        // Plenty of dishes have no photo. Not an error state,
                        // and a sheet is not the place to start treating it as
                        // one.
                        fallback: GradientImagePlaceholder(
                          seed: item.id,
                          icon: Icons.fastfood_rounded,
                          iconSize: 44,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: ZopiqSpacing.md,
                    bottom: -18,
                    // Its own surface and shadow, because it is sitting on a
                    // photograph: the button's border alone cannot be trusted to
                    // separate it from whatever the picture happens to be behind
                    // that corner.
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 3,
                      shadowColor: Colors.black.withValues(alpha: 0.28),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AddToCartControl.radius),
                      ),
                      child: AddToCartControl(
                        width: 104,
                        // A customisable dish always shows ADD: every tap can
                        // build a different configuration, so there is no single
                        // line for a stepper to count. Same rule as the menu row.
                        quantity: item.isCustomizable ? 0 : quantity,
                        enabled: enabled,
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
                    ),
                  ),
                ],
              ),
              // The overhang's 18pt, plus the gap the layout wanted anyway.
              const SizedBox(height: ZopiqSpacing.lg + 18),

              Row(
                children: <Widget>[
                  ZopiqVegIndicator(isVeg: item.isVeg),
                  if (item.isBestseller) ...<Widget>[
                    const SizedBox(width: ZopiqSpacing.sm),
                    _Tag(
                      icon: Icons.star_rounded,
                      label: 'Bestseller',
                      color: zc.primaryDeep,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: ZopiqSpacing.xs),

              Text(
                item.name,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ZopiqSpacing.xs),

              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '₹${item.price}',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  // The restaurant's stated former price, after the live one and
                  // muted, so the number that is charged is the one the eye lands
                  // on first. It is never what anyone pays.
                  if (item.originalPrice != null) ...<Widget>[
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      '₹${item.originalPrice}',
                      style: t.bodyMedium?.copyWith(
                        color: zc.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  if (item.isCustomizable) ...<Widget>[
                    const SizedBox(width: ZopiqSpacing.sm),
                    Text(
                      'onwards',
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ],
              ),

              if (item.rating != null || item.prepMinutes != null) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.sm),
                Row(
                  children: <Widget>[
                    if (item.rating != null)
                      _Tag(
                        icon: Icons.star_rounded,
                        label: item.rating!.toStringAsFixed(1),
                        color: zc.rating,
                      ),
                    if (item.rating != null && item.prepMinutes != null)
                      const SizedBox(width: ZopiqSpacing.md),
                    if (item.prepMinutes != null)
                      _Tag(
                        icon: Icons.schedule_rounded,
                        label: '${item.prepMinutes} min to prepare',
                        color: zc.textMuted,
                      ),
                  ],
                ),
              ],

              if (item.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.lg),
                Text(
                  item.description,
                  // Unclipped, unlike the row's two lines. Being able to read the
                  // whole description is most of why this sheet exists.
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],

              if (item.isCustomizable) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.lg),
                Text(
                  'Choices',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                for (final MenuOptionGroup g in item.optionGroups)
                  Padding(
                    padding: const EdgeInsets.only(top: ZopiqSpacing.xs),
                    child: Text(
                      // Named, not offered. Tapping Add opens the sheet that
                      // actually takes the choices, and asking the same questions
                      // in two places would leave two answers to reconcile.
                      '${g.name} · ${g.options.map((MenuOption o) => o.name).join(', ')}',
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ),
              ],

              _AddOnRail(
                item: item,
                restaurantId: restaurantId,
                restaurantName: restaurantName,
                enabled: enabled,
              ),
            ],
          ),
        ),

        // **No bottom bar.** It held the price and the Add control, and both
        // moved: the control onto the photo, and the price is three lines under
        // the dish name where it was already being shown. A bar repeating a
        // number the customer can see, under a button that is now somewhere
        // else, is a bar with nothing left to say — and it was costing ~70pt of
        // a sheet that has better uses for them.
        const SafeArea(top: false, child: SizedBox.shrink()),
      ],
    );
  }
}

/// Other dishes from the same kitchen, along the bottom of the sheet.
///
/// The Zomato move, and the reason it works: somebody reading one dish in
/// detail is deciding, and the cheapest thing to put in front of a person who is
/// deciding is the thing that goes *with* what they are looking at. Everything
/// here is from the restaurant already open, so adding one never provokes the
/// "start a new cart?" dialog.
///
/// Silent when there is nothing worth showing — a one-dish menu, a menu still
/// loading, or a failure. A rail that renders a spinner or an error inside a
/// sheet about something else is noise; the dish the customer actually opened is
/// unaffected either way.
class _AddOnRail extends ConsumerWidget {
  const _AddOnRail({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
    required this.enabled,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;
  final bool enabled;

  /// Enough to be worth swiping, few enough that the sheet does not turn into a
  /// second menu.
  static const int _max = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    final List<MenuCategory> menu =
        ref.watch(menuProvider(restaurantId)).valueOrNull ??
        const <MenuCategory>[];

    // The *whole* menu, flattened and then ordered by how likely a dish is to
    // read as a companion rather than as a second main: bestsellers first, then
    // anything with a photograph, then the cheaper things. Price ascending last
    // because an add-on is by definition the smaller half of the order.
    final List<MenuItem> candidates =
        <MenuItem>[
            for (final MenuCategory c in menu)
              for (final MenuItem i in c.items)
                if (i.id != item.id) i,
          ]
          ..sort((MenuItem a, MenuItem b) {
            if (a.isBestseller != b.isBestseller) {
              return a.isBestseller ? -1 : 1;
            }
            final bool aPhoto = a.imageUrl.isNotEmpty;
            final bool bPhoto = b.imageUrl.isNotEmpty;
            if (aPhoto != bPhoto) return aPhoto ? -1 : 1;
            return a.price.compareTo(b.price);
          });

    if (candidates.isEmpty) return const SizedBox.shrink();
    final List<MenuItem> shown = candidates.take(_max).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: ZopiqSpacing.xl),
        Divider(color: zc.divider, height: 1),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(
          'Goes well with',
          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ZopiqSpacing.xxs),
        Text(
          'Also from $restaurantName',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        SizedBox(
          // Tall enough for a 4:3 photo, two lines of name, and the price row
          // under it. Fixed because a horizontal list has to be given a height —
          // and because ragged card heights down a rail read as broken.
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The gutter is already on the ListView above, so the rail would
            // otherwise stop short of the screen edge on both sides. This lets
            // it bleed to the edges the way every other rail in the app does.
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.xxs,
            ),
            itemCount: shown.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: ZopiqSpacing.md),
            itemBuilder: (BuildContext context, int i) => _AddOnCard(
              item: shown[i],
              restaurantId: restaurantId,
              restaurantName: restaurantName,
              enabled: enabled,
            ),
          ),
        ),
      ],
    );
  }
}

/// One dish in the [_AddOnRail].
class _AddOnCard extends ConsumerWidget {
  const _AddOnCard({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
    required this.enabled,
  });

  final MenuItem item;
  final String restaurantId;
  final String restaurantName;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;
    final int quantity = ref.watch(
      cartProvider.select((c) => c.quantityOf(item.id)),
    );

    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: ZopiqRadii.rMd,
                  child: ZopiqNetworkImage(
                    url: item.imageUrl,
                    fallback: GradientImagePlaceholder(
                      seed: item.id,
                      icon: Icons.fastfood_rounded,
                      iconSize: 28,
                    ),
                  ),
                ),
              ),
              // The same overlap as the main photo above, at the rail's scale —
              // so the gesture that adds a dish is in the same place whichever
              // of the two the customer is looking at.
              Positioned(
                right: ZopiqSpacing.xs,
                bottom: -14,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 3,
                  shadowColor: Colors.black.withValues(alpha: 0.28),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AddToCartControl.radius),
                  ),
                  child: AddToCartControl(
                    width: 82,
                    quantity: item.isCustomizable ? 0 : quantity,
                    enabled: enabled,
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
                ),
              ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.md + 14),
          Row(
            children: <Widget>[
              ZopiqVegIndicator(isVeg: item.isVeg, size: 12),
              if (item.isBestseller) ...<Widget>[
                const SizedBox(width: ZopiqSpacing.xxs),
                Icon(Icons.star_rounded, size: 12, color: zc.primaryDeep),
              ],
            ],
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            item.isCustomizable ? '₹${item.price} onwards' : '₹${item.price}',
            style: t.bodySmall?.copyWith(
              color: zc.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: ZopiqSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
