import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';
import 'package:zopiq_vendor/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiq_vendor/features/menu/presentation/widgets/dish_editor.dart';

/// One dish in the menu, with its price, its food-type mark, and the switch the
/// kitchen actually reaches for: available or not. Tap the row to edit it.
///
/// The switch is optimistic — it flips the instant it is pressed, because a
/// kitchen marking a dish sold out mid-rush cannot wait on a round trip, and the
/// write almost always succeeds. If it doesn't, the switch goes back and a
/// message says why, which is the honest version of "we didn't actually do that".
class DishRow extends ConsumerStatefulWidget {
  const DishRow({required this.dish, super.key});

  final VendorDish dish;

  @override
  ConsumerState<DishRow> createState() => _DishRowState();
}

class _DishRowState extends ConsumerState<DishRow> {
  /// The switch's own reading, held locally so it can flip before the server
  /// confirms. Seeded from the row and re-seeded whenever the list re-fetches
  /// (an add or edit rebuilds this widget with fresh data).
  late bool _available = widget.dish.isAvailable;
  bool _busy = false;

  @override
  void didUpdateWidget(DishRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dish.isAvailable != widget.dish.isAvailable) {
      _available = widget.dish.isAvailable;
    }
  }

  Future<void> _toggle(bool next) async {
    setState(() {
      _available = next;
      _busy = true;
    });
    final String? failure = await ref
        .read(menuControllerProvider.notifier)
        .setAvailability(dishId: widget.dish.id, isAvailable: next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Put it back if the write was refused. The list was never re-fetched, so
      // the local reading is the only thing that moved and the only thing to undo.
      if (failure != null) _available = !next;
    });
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final VendorDish dish = widget.dish;

    // A dish that is off reads as off: its text dims so a glance down the menu
    // shows what is live without reading a single switch.
    final Color nameColor = _available ? zc.textStrong : zc.textMuted;

    return InkWell(
      onTap: () => showDishEditor(context, dish: dish),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (dish.imageUrl.isNotEmpty) ...<Widget>[
              ClipRRect(
                borderRadius: ZopiqRadii.rSm,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: ZopiqNetworkImage(
                    url: dish.imageUrl,
                    fallback: ColoredBox(color: zc.shimmerBase),
                  ),
                ),
              ),
              const SizedBox(width: ZopiqSpacing.md),
            ],
            Padding(
              padding: const EdgeInsets.only(top: ZopiqSpacing.xxs),
              child: ZopiqVegIndicator(isVeg: dish.isVeg, size: 16),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (dish.isBestseller) ...<Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.star_rounded, size: 13, color: zc.rating),
                        const SizedBox(width: ZopiqSpacing.xxs),
                        Text(
                          'Bestseller',
                          style: t.labelSmall?.copyWith(
                            color: zc.rating,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZopiqSpacing.xxs),
                  ],
                  Text(
                    dish.name,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: nameColor,
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    '₹${dish.price}',
                    style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  ),
                  if (dish.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      dish.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Switch(
                  value: _available,
                  activeTrackColor: zc.primary,
                  onChanged: _busy ? null : _toggle,
                ),
                Text(
                  _available ? 'Available' : 'Sold out',
                  style: t.labelSmall?.copyWith(
                    color: _available ? zc.textMuted : zc.nonVeg,
                    fontWeight: _available ? null : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
