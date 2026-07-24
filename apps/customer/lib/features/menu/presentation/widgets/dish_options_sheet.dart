import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_option.dart';

/// Choose a customisable dish's variant and add-ons before it goes in the cart.
///
/// Pops the flat list of chosen [MenuOption]s on "Add", or null if dismissed.
/// The list is exactly what the order service is sent as this line's options.
Future<List<MenuOption>?> showDishOptionsSheet(
  BuildContext context, {
  required MenuItem item,
}) => showModalBottomSheet<List<MenuOption>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _DishOptionsSheet(item: item),
);

class _DishOptionsSheet extends StatefulWidget {
  const _DishOptionsSheet({required this.item});

  final MenuItem item;

  @override
  State<_DishOptionsSheet> createState() => _DishOptionsSheetState();
}

class _DishOptionsSheetState extends State<_DishOptionsSheet> {
  /// Chosen option ids per group id.
  final Map<String, Set<String>> _selected = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    // A variant defaults to its first option, so there is always a valid choice
    // and a price to show; add-on groups start empty.
    for (final MenuOptionGroup g in widget.item.optionGroups) {
      _selected[g.id] = <String>{
        if (g.isVariant && g.options.isNotEmpty) g.options.first.id,
      };
    }
  }

  List<MenuOption> get _chosen => <MenuOption>[
    for (final MenuOptionGroup g in widget.item.optionGroups)
      ...g.options.where((MenuOption o) => _selected[g.id]!.contains(o.id)),
  ];

  int get _unitPrice =>
      widget.item.price +
      _chosen.fold(0, (int s, MenuOption o) => s + o.priceDelta);

  /// Every required group has its minimum met. Variants always do (defaulted);
  /// this guards required add-on groups.
  bool get _satisfied => widget.item.optionGroups.every(
    (MenuOptionGroup g) => _selected[g.id]!.length >= g.minSelect,
  );

  void _toggle(MenuOptionGroup g, MenuOption o) {
    setState(() {
      final Set<String> sel = _selected[g.id]!;
      if (g.isVariant) {
        // Radios: exactly one.
        sel
          ..clear()
          ..add(o.id);
      } else if (sel.contains(o.id)) {
        sel.remove(o.id);
      } else if (sel.length < g.maxSelect) {
        sel.add(o.id);
      }
      // Silently ignore a tap that would exceed an add-on group's max — the
      // customer sees the box simply not tick, which reads as "that's the limit".
    });
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.pageGutter,
                0,
                ZopiqSpacing.pageGutter,
                ZopiqSpacing.md,
              ),
              children: <Widget>[
                Text(
                  widget.item.name,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Customise it your way',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
                const SizedBox(height: ZopiqSpacing.md),
                for (final MenuOptionGroup g in widget.item.optionGroups)
                  _GroupSection(
                    group: g,
                    selected: _selected[g.id]!,
                    onTap: (MenuOption o) => _toggle(g, o),
                  ),
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
              child: ZopiqButton(
                label: 'Add item · ₹$_unitPrice',
                variant: ZopiqButtonVariant.cta,
                onPressed: _satisfied
                    ? () => Navigator.of(context).pop(_chosen)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final MenuOptionGroup group;
  final Set<String> selected;
  final ValueChanged<MenuOption> onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: ZopiqSpacing.sm),
        Row(
          children: <Widget>[
            Text(
              group.name,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Text(
              group.isVariant
                  ? 'Required'
                  : 'Up to ${group.maxSelect}',
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
          ],
        ),
        for (final MenuOption o in group.options)
          _OptionTile(
            option: o,
            isVariant: group.isVariant,
            selected: selected.contains(o.id),
            onTap: () => onTap(o),
          ),
        const Divider(height: ZopiqSpacing.lg),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.isVariant,
    required this.selected,
    required this.onTap,
  });

  final MenuOption option;
  final bool isVariant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.xs),
        child: Row(
          children: <Widget>[
            Icon(
              isVariant
                  ? (selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded)
                  : (selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded),
              color: selected ? zc.primary : zc.textMuted,
              size: 22,
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(child: Text(option.name, style: t.bodyMedium)),
            Text(
              option.priceDelta == 0 ? '' : '+₹${option.priceDelta}',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
