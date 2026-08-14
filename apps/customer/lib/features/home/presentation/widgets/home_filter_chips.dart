import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

/// The chip row that filters and sorts the restaurant list. Pins below the app
/// bar once the list scrolls under it, as Swiggy's does.
class HomeFilterChips extends ConsumerWidget {
  const HomeFilterChips({super.key});

  /// A chip is ~34 tall (label + `sm` padding + border), so 60 left roughly 13
  /// of dead air above and below it. 48 leaves the chips breathing without the
  /// band reading as an empty stripe between the category rail and the first
  /// section.
  static const double height = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeFilters filters = ref.watch(homeFiltersProvider);
    final HomeFiltersNotifier notifier = ref.read(homeFiltersProvider.notifier);

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(
        height: height,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: ZopiqSpacing.pagePadding,
          physics: const BouncingScrollPhysics(),
          children: <Widget>[
            _SortChip(sort: filters.sort, onSelected: notifier.setSort),
            const SizedBox(width: ZopiqSpacing.sm),
            _FilterChip(
              label: 'Fast Delivery',
              selected: filters.fastDelivery,
              onTap: notifier.toggleFastDelivery,
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            _FilterChip(
              label: 'Rating 4.0+',
              selected: filters.ratingAbove4,
              onTap: notifier.toggleRatingAbove4,
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            _FilterChip(
              label: 'Pure Veg',
              selected: filters.pureVeg,
              onTap: notifier.togglePureVeg,
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            _FilterChip(
              label: 'Great Offers',
              selected: filters.greatOffers,
              onTap: notifier.toggleGreatOffers,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surface = Theme.of(context).colorScheme.surface;

    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: ZopiqRadii.rPill,
        child: AnimatedContainer(
          duration: ZopiqDurations.fast,
          curve: ZopiqCurves.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.md,
            vertical: ZopiqSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? zc.primary.withValues(alpha: 0.12) : surface,
            borderRadius: ZopiqRadii.rPill,
            border: Border.all(color: selected ? zc.primary : zc.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? zc.primary : zc.textStrong,
                ),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: ZopiqSpacing.xs),
                Icon(ZopiqIcons.close, size: 14, color: zc.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.sort, required this.onSelected});

  final HomeSort sort;
  final ValueChanged<HomeSort> onSelected;

  Future<void> _openSheet(BuildContext context) async {
    final HomeSort? picked = await showModalBottomSheet<HomeSort>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (BuildContext sheetContext) {
        return _SortSheet(current: sort);
      },
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final bool active = sort != HomeSort.relevance;
    return _FilterChip(
      label: active ? sort.label : 'Sort by',
      selected: active,
      onTap: () => _openSheet(context),
    );
  }
}

/// What each sort order *means*, and the glyph that stands for it.
///
/// The labels alone were doing all the work — five lines of near-identical text
/// beside five identical radio buttons, where the only way to tell "Delivery
/// time" from "Rating: high to low" was to read both carefully. An icon and a
/// line of plain English make the row scannable, and they cost nothing at the
/// call site because they hang off the enum rather than off the sheet.
({IconData icon, String blurb}) _sortMeta(HomeSort sort) {
  switch (sort) {
    case HomeSort.relevance:
      return (
        icon: ZopiqIcons.sparkle,
        blurb: 'What we think you will like',
      );
    case HomeSort.rating:
      return (
        icon: ZopiqIcons.star,
        blurb: 'Best rated kitchens first',
      );
    case HomeSort.deliveryTime:
      return (
        icon: ZopiqIcons.timer,
        blurb: 'Quickest to reach you',
      );
    case HomeSort.costLowToHigh:
      return (
        icon: ZopiqIcons.trendDown,
        blurb: 'Cheapest first',
      );
    case HomeSort.costHighToLow:
      return (
        icon: ZopiqIcons.trendUp,
        blurb: 'Most expensive first',
      );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});

  final HomeSort current;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.lg,
              ZopiqSpacing.sm,
              ZopiqSpacing.lg,
              ZopiqSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  ZopiqIcons.sliders,
                  size: 20,
                  color: zc.textStrong,
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                Text(
                  'Sort by',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                // Only offered once it does something. "Reset" beside an
                // untouched list is a control that cannot be used.
                if (current != HomeSort.relevance)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, HomeSort.relevance),
                    child: const Text('Reset'),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.md,
                0,
                ZopiqSpacing.md,
                ZopiqSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final HomeSort option in HomeSort.values)
                    _SortOptionTile(
                      option: option,
                      selected: option == current,
                      onTap: () => Navigator.pop(context, option),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One sort order as a card: glyph, label, what it does, and a tick.
class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final HomeSort option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final ({IconData icon, String blurb}) meta = _sortMeta(option);

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Material(
        color: selected
            ? zc.primary.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: ZopiqRadii.rMd,
        child: InkWell(
          borderRadius: ZopiqRadii.rMd,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.md,
              vertical: ZopiqSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: ZopiqRadii.rMd,
              border: Border.all(
                color: selected ? zc.primary : zc.divider,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  meta.icon,
                  size: 20,
                  color: selected ? zc.primary : zc.textMuted,
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        option.label,
                        style: t.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? zc.primary : zc.textStrong,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        meta.blurb,
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
                // The tick occupies its slot either way, so the rows do not
                // shift sideways as the selection moves down the list.
                Icon(
                  selected
                      ? ZopiqIconsFill.checkCircle
                      : ZopiqIcons.circle,
                  size: 20,
                  color: selected ? zc.primary : zc.divider,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes [HomeFilterChips] usable as a pinned sliver, with dynamic height.
class HomeFilterChipsHeader extends SliverPersistentHeaderDelegate {
  const HomeFilterChipsHeader({this.heightFactor = 1.0});

  final double heightFactor;

  @override
  double get minExtent => HomeFilterChips.height;

  @override
  double get maxExtent => HomeFilterChips.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // heightFactor animates from 1.0 (visible) to 0.0 (hidden).
    // By keeping the layout extent fixed, we prevent any scroll jumps or dead zones.
    // The Transform visually slides the bar up, revealing the content scrolling underneath it.
    final double dy = -HomeFilterChips.height * (1.0 - heightFactor);
    return ClipRect(
      child: Transform.translate(
        offset: Offset(0, dy),
        child: const HomeFilterChips(),
      ),
    );
  }

  @override
  bool shouldRebuild(HomeFilterChipsHeader oldDelegate) =>
      heightFactor != oldDelegate.heightFactor;
}
