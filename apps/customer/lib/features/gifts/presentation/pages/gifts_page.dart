import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_card.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_sheet.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_shop_card.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_status_views.dart';

/// The Gifts tab — a curated storefront for handcrafted gifts, artisanal decor,
/// personalized tokens, and luxury gift boxes.
class GiftsPage extends ConsumerStatefulWidget {
  const GiftsPage({required this.onOpenShop, super.key});

  final void Function(GiftShop shop) onOpenShop;

  @override
  ConsumerState<GiftsPage> createState() => _GiftsPageState();
}

class _GiftsPageState extends ConsumerState<GiftsPage> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GiftItem> _filterItems(List<GiftItem> items) {
    return items.where((GiftItem item) {
      final bool matchesCategory =
          _selectedCategory == 'All' ||
          item.category.toLowerCase() == _selectedCategory.toLowerCase();
      final bool matchesSearch =
          _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.category.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<GiftItem>> items = ref.watch(giftItemsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        color: ZopiqPalette.primaryDeep,
        backgroundColor: ZopiqPalette.white,
        onRefresh: () {
          ref.invalidate(giftShopsProvider);
          return ref.refresh(giftItemsProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: <Widget>[
            const _GiftsAppBar(),
            _HeroGiftBanner(
              searchController: _searchController,
              onSearchChanged: (String query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
            _GiftShopsRail(onOpenShop: widget.onOpenShop),
            items.when(
              loading: () => const SliverToBoxAdapter(child: GiftGridSkeleton()),
              error: (Object error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: GiftErrorView(
                  message: error is GiftLoadFailure
                      ? error.message
                      : 'Please check your connection and try again.',
                  onRetry: () => ref.invalidate(giftItemsProvider),
                ),
              ),
              data: (List<GiftItem> list) {
                final List<String> categories = <String>[
                  'All',
                  ...list.map((GiftItem item) => item.category).toSet(),
                ];
                final List<GiftItem> filtered = _filterItems(list);

                return SliverMainAxisGroup(
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: _CategoryFilterRail(
                        categories: categories,
                        selectedCategory: _selectedCategory,
                        onSelectCategory: (String cat) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                        },
                      ),
                    ),
                    if (filtered.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: GiftEmptyView(),
                      )
                    else
                      _GiftGrid(items: filtered),
                  ],
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

class _GiftsAppBar extends StatelessWidget {
  const _GiftsAppBar();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: ZopiqSpacing.pageGutter,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.card_giftcard_rounded, color: zc.primaryDeep, size: 26),
              const SizedBox(width: ZopiqSpacing.sm),
              Text(
                'Gifts',
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 34),
            child: Text(
              'Handcrafted & curated things to gift someone',
              style: t.bodySmall?.copyWith(color: zc.textMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
      toolbarHeight: 64,
    );
  }
}

class _HeroGiftBanner extends StatelessWidget {
  const _HeroGiftBanner({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.sm,
        ),
        child: Column(
          children: <Widget>[
            // Ambient Hero Card
            Container(
              padding: const EdgeInsets.all(ZopiqSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    zc.primaryDeep.withValues(alpha: isDark ? 0.25 : 0.12),
                    zc.primaryDeep.withValues(alpha: isDark ? 0.1 : 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: ZopiqRadii.rXl,
                border: Border.all(
                  color: zc.primaryDeep.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.sm,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: zc.primaryDeep,
                            borderRadius: ZopiqRadii.rPill,
                          ),
                          child: Text(
                            'STUDIO CURATED',
                            style: t.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: ZopiqSpacing.xs),
                        Text(
                          'Make Every Moment Special',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Handmade gifts, artisan boxes & custom notes',
                          style: t.bodySmall?.copyWith(
                            color: zc.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.md),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: zc.primaryDeep.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.card_giftcard_rounded,
                      color: zc.primaryDeep,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            // Search Input Field
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search handcrafted gifts, candles, frames...',
                hintStyle: t.bodyMedium?.copyWith(
                  color: zc.textMuted,
                  fontSize: 13,
                ),
                prefixIcon: Icon(Icons.search_rounded, color: zc.textMuted, size: 20),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.md,
                  vertical: ZopiqSpacing.sm,
                ),
                border: const OutlineInputBorder(
                  borderRadius: ZopiqRadii.rPill,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFilterRail extends StatelessWidget {
  const _CategoryFilterRail({
    required this.categories,
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeader(title: 'Browse By Category'),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.pageGutter,
            ),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              final String cat = categories[index];
              final bool isSelected = cat == selectedCategory;
              return ChoiceChip(
                label: Text(cat),
                selected: isSelected,
                onSelected: (_) => onSelectCategory(cat),
                selectedColor: zc.primaryDeep,
                backgroundColor: Theme.of(context).colorScheme.surface,
                labelStyle: t.labelSmall?.copyWith(
                  color: isSelected ? Colors.white : zc.textStrong,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: ZopiqRadii.rPill,
                  side: BorderSide(
                    color: isSelected
                        ? zc.primaryDeep
                        : zc.divider,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.xs,
                  vertical: 2,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GiftShopsRail extends ConsumerWidget {
  const _GiftShopsRail({required this.onOpenShop});

  final void Function(GiftShop shop) onOpenShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<GiftShop> shops =
        ref.watch(giftShopsProvider).valueOrNull ?? const <GiftShop>[];
    if (shops.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(title: 'Gift Shops'),
          SizedBox(
            height: 195,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
              ),
              itemCount: shops.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: ZopiqSpacing.md),
              itemBuilder: (BuildContext context, int i) => GiftShopCard(
                shop: shops[i],
                onTap: () => onOpenShop(shops[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftGrid extends StatelessWidget {
  const _GiftGrid({required this.items});

  final List<GiftItem> items;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final double width = constraints.crossAxisExtent;
        final int crossAxisCount = width > 900 ? 4 : (width > 550 ? 3 : 2);
        final double childAspectRatio = width < 400 ? 0.62 : 0.66;

        return SliverMainAxisGroup(
          slivers: <Widget>[
            const SliverToBoxAdapter(child: _SectionHeader(title: 'All Gifts')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.lg,
                0,
                ZopiqSpacing.lg,
                ZopiqSpacing.lg,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: ZopiqSpacing.lg,
                  crossAxisSpacing: ZopiqSpacing.lg,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    return RepaintBoundary(
                      child: GiftItemCard(
                        item: items[i],
                        onTap: () => showGiftItemSheet(context, items[i]),
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }
}
