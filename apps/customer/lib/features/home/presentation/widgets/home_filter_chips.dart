import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/presentation/providers/home_filters.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

/// The chip row that filters and sorts the restaurant list. Pins below the app
/// bar once the list scrolls under it, as Swiggy's does.
class HomeFilterChips extends ConsumerWidget {
  const HomeFilterChips({super.key});

  static const double height = 60;

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
                Icon(Icons.close_rounded, size: 14, color: zc.primary),
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
      builder: (BuildContext sheetContext) => _SortSheet(current: sort),
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

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});

  final HomeSort current;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.lg,
              0,
              ZopiqSpacing.lg,
              ZopiqSpacing.sm,
            ),
            child: Text(
              'Sort by',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          RadioGroup<HomeSort>(
            groupValue: current,
            onChanged: (HomeSort? value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final HomeSort option in HomeSort.values)
                  RadioListTile<HomeSort>(
                    value: option,
                    activeColor: zc.primary,
                    title: Text(
                      option.label,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
        ],
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
