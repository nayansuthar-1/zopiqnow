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

  /// The sold-out note, held locally for the same reason [_available] is: it is
  /// written without a re-fetch, so this is the only copy that moves.
  late String _reason = widget.dish.unavailableReason;
  bool _busy = false;

  @override
  void didUpdateWidget(DishRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dish.isAvailable != widget.dish.isAvailable) {
      _available = widget.dish.isAvailable;
    }
    if (oldWidget.dish.unavailableReason != widget.dish.unavailableReason) {
      _reason = widget.dish.unavailableReason;
    }
  }

  Future<void> _toggle(bool next) async {
    // Deliberately does not stop to ask why. The switch is the hot path of a
    // rush and has to stay one tap; the reason is offered afterwards, on the row
    // itself, where it costs nothing to skip.
    setState(() {
      _available = next;
      if (next) _reason = '';
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
      if (failure != null) {
        _available = !next;
        _reason = widget.dish.unavailableReason;
      }
    });
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  /// Why this dish is off — asked after the fact, never before it. The presets
  /// are the four answers a kitchen actually gives; "Something else" opens the
  /// editor, where there is room to type.
  Future<void> _askReason() async {
    const List<String> presets = <String>[
      'Ingredients are over',
      'Not prepared today',
      'Equipment is down',
      'Off the menu for now',
    ];

    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.pageGutter,
                0,
                ZopiqSpacing.pageGutter,
                ZopiqSpacing.sm,
              ),
              child: Text(
                'Why is ${widget.dish.name} off?',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final String preset in presets)
              ListTile(
                title: Text(preset),
                trailing: _reason == preset
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, preset),
              ),
            if (_reason.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Clear the reason'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
            const SizedBox(height: ZopiqSpacing.sm),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final String previous = _reason;
    setState(() {
      _reason = picked;
      _busy = true;
    });
    final String? failure = await ref
        .read(menuControllerProvider.notifier)
        .setAvailability(
          dishId: widget.dish.id,
          isAvailable: false,
          reason: picked,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure != null) _reason = previous;
    });
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  /// "8:00 AM – 11:00 AM", or "10:00 PM – 2:00 AM +1" when the window runs past
  /// midnight. Formatted through [TimeOfDay.format], so it follows the device's
  /// 12/24-hour setting rather than picking one for the kitchen.
  static String _windowLabel(BuildContext context, VendorDish dish) {
    String at(int minutes) =>
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);
    final String span =
        '${at(dish.serveFromMinutes!)} – ${at(dish.serveToMinutes!)}';
    return dish.windowCrossesMidnight ? '$span +1' : span;
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
                  Row(
                    children: <Widget>[
                      Text(
                        '₹${dish.price}',
                        style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      ),
                      // The struck-through number, when there is one. It sits
                      // *after* the live price and dimmer than it, so the price
                      // that will actually be charged is the one read first.
                      if (dish.originalPrice != null) ...<Widget>[
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          '₹${dish.originalPrice}',
                          style: t.bodySmall?.copyWith(
                            color: zc.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      if (dish.prepMinutes != null) ...<Widget>[
                        const SizedBox(width: ZopiqSpacing.sm),
                        Text(
                          '${dish.prepMinutes} min',
                          style: t.labelSmall?.copyWith(color: zc.textMuted),
                        ),
                      ],
                    ],
                  ),
                  if (dish.hasServingWindow) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: zc.textMuted,
                        ),
                        const SizedBox(width: ZopiqSpacing.xxs),
                        Text(
                          _windowLabel(context, dish),
                          style: t.labelSmall?.copyWith(color: zc.textMuted),
                        ),
                      ],
                    ),
                  ],
                  if (dish.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      dish.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                  // Only while it is off, because that is the only time it is
                  // true — and it is a button, not a label, so a kitchen that
                  // flipped the switch mid-rush can come back and say why in one
                  // tap, or never, without either being the wrong answer.
                  if (!_available) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xs),
                    InkWell(
                      borderRadius: ZopiqRadii.rSm,
                      onTap: _busy ? null : _askReason,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: ZopiqSpacing.xxs,
                        ),
                        child: Text(
                          _reason.isEmpty ? 'Add a reason' : _reason,
                          style: t.labelSmall?.copyWith(
                            color: _reason.isEmpty ? zc.primary : zc.textMuted,
                            fontWeight: _reason.isEmpty
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      ),
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
