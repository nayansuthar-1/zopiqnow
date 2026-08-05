import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/dish_add_flow.dart';

/// The whole dish, opened by tapping its row on the menu.
///
/// The row is a summary and has to stay one: it is 118pt of art beside two lines
/// of description, repeated a hundred times down a scrolling menu. Everything a
/// restaurant can say about a dish does not fit there and should not — the photo
/// is a thumbnail, the description is clipped at two lines, and a serving window
/// or a prep time has nowhere to go at all. This is where the rest of it lives.
///
/// **Seventy per cent of the screen, deliberately fixed.** Enough for a photo
/// that reads as a photograph and the text under it, while leaving the menu
/// visible above — so the sheet reads as a closer look at a row that is still
/// there, not as a page the customer has navigated to and must come back from.
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
      // would ask for 70% of a taller box than exists and overflow by exactly
      // the notch on the phones that have one.
      heightFactor: 0.7,
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
              AspectRatio(
                // Wider than the row's 118×96 thumbnail: at this size the photo
                // is the point of the sheet rather than an identifier for a line
                // of text.
                aspectRatio: 16 / 10,
                child: ClipRRect(
                  borderRadius: ZopiqRadii.rMd,
                  child: ZopiqNetworkImage(
                    url: item.imageUrl,
                    // Plenty of dishes have no photo. Not an error state, and a
                    // sheet is not the place to start treating it as one.
                    fallback: GradientImagePlaceholder(
                      seed: item.id,
                      icon: Icons.fastfood_rounded,
                      iconSize: 44,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),

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
            ],
          ),
        ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.sm,
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.md,
            ),
            // Price on the left, the control on the right — the same shape a
            // product page has, and the reason the control is not stretched
            // across the bar: it is the *same* widget the menu row uses, at the
            // same size, so the thing the customer just tapped past is the thing
            // they are tapping now.
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.isCustomizable
                        ? '₹${item.price} onwards'
                        : '₹${item.price}',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                AddToCartControl(
                  width: 140,
                  // A customisable dish always shows ADD: every tap can build a
                  // different configuration, so there is no single line for a
                  // stepper to count. Same rule as the menu row.
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
              ],
            ),
          ),
        ),
      ],
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
