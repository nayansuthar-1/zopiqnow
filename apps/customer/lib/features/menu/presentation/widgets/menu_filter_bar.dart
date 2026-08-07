import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

/// The filter row, pinned so it stays reachable a hundred dishes down.
///
/// Pinned is the whole reason this is a [SliverPersistentHeader] rather than one
/// more box in the list: a filter that scrolls away is one the customer has to
/// scroll back up to find, and on a menu this long they simply do not.
class MenuFilterBar extends StatelessWidget {
  const MenuFilterBar({super.key});

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _FilterBarDelegate(
        background: Theme.of(context).colorScheme.surface,
        divider: context.zc.divider,
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  const _FilterBarDelegate({required this.background, required this.divider});

  final Color background;
  final Color divider;

  @override
  double get minExtent => MenuFilterBar.height;
  @override
  double get maxExtent => MenuFilterBar.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      // The colour belongs *inside* the decoration. Passing both is an assertion
      // failure, not a warning — and because this is a pinned sliver header, the
      // throw takes the viewport's layout with it and the whole restaurant page
      // renders white.
      //
      // The line is what stops the chips floating over the dish they are pinned
      // above; without it they read as part of whatever has scrolled under them.
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      alignment: Alignment.centerLeft,
      child: const _FilterChips(),
    );
  }

  @override
  bool shouldRebuild(_FilterBarDelegate old) =>
      old.background != background || old.divider != divider;
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool vegOnly = ref.watch(vegOnlyProvider);
    final bool bestsellers = ref.watch(bestsellersOnlyProvider);

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
      children: <Widget>[
        _Chip(
          label: 'Veg only',
          icon: Icons.eco_rounded,
          selected: vegOnly,
          selectedColor: context.zc.veg,
          onTap: () => ref.read(vegOnlyProvider.notifier).toggle(),
        ),
        const SizedBox(width: ZopiqSpacing.sm),
        _Chip(
          label: 'Bestsellers',
          icon: Icons.star_rounded,
          selected: bestsellers,
          selectedColor: context.zc.primaryDeep,
          onTap: () => ref.read(bestsellersOnlyProvider.notifier).state =
              !bestsellers,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Color fg = selected ? selectedColor : zc.textStrong;

    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZopiqRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.md,
            vertical: ZopiqSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? selectedColor.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(color: selected ? selectedColor : zc.divider),
            borderRadius: BorderRadius.circular(ZopiqRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: ZopiqSpacing.xs),
              Text(
                label,
                style: t.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: ZopiqSpacing.xs),
                Icon(Icons.close_rounded, size: 14, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "Menu" button's sheet: every section, with its dish count, as a
/// way to get from the top of a hundred-dish menu to Desserts.
///
/// Pops the index of the chosen category, or null if dismissed.
Future<int?> showMenuJumpSheet(
  BuildContext context, {
  required List<MenuCategory> categories,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) {
    final TextTheme t = Theme.of(sheetContext).textTheme;
    final ZopiqColors zc = sheetContext.zc;

    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Column(
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
              'Menu',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            // Rows built by hand rather than with `ListTile`, which is ~56 tall
            // whatever you put in it — most of that being padding around one
            // line of text. At 48 the sheet shows two or three more sections
            // for the same height, and 48 is exactly the minimum comfortable
            // tap target, so nothing is traded for it.
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
              itemCount: categories.length,
              itemBuilder: (BuildContext context, int i) => InkWell(
                onTap: () => Navigator.of(context).pop(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.pageGutter,
                    vertical: ZopiqSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      // Expanded and clipped: a section called "Chinese Starters
                      // and Soups" beside its count is the one thing on this
                      // sheet that can overflow a row.
                      Expanded(
                        child: Text(
                          categories[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyLarge,
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Text(
                        '${categories[i].items.length}',
                        style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  },
);
