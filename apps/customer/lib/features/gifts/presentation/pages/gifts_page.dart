import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_bag_bar.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_card.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_sheet.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_shop_card.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_status_views.dart';

/// The Gifts tab — a Blinkit-inspired quick-commerce storefront for handcrafted gifts,
/// artisanal decor, personalized tokens, and luxury gift hampers delivered in minutes.
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

  static const Color _blinkitGreen = Color(0xFF0C831F);

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
      // Draws nothing until there is something in the bag.
      bottomNavigationBar: const GiftBagBar(),
      body: RefreshIndicator.adaptive(
        color: _blinkitGreen,
        backgroundColor: Colors.white,
        onRefresh: () {
          ref.invalidate(giftShopsProvider);
          return ref.refresh(giftItemsProvider.future);
        },
        child: NotificationListener<UserScrollNotification>(
          onNotification: (UserScrollNotification notification) {
            if (notification.metrics.axis == Axis.vertical) {
              if (notification.direction == ScrollDirection.reverse && notification.metrics.pixels > 60) {
                if (ref.read(bottomNavVisibilityProvider)) {
                  ref.read(bottomNavVisibilityProvider.notifier).state = false;
                }
              } else if (notification.direction == ScrollDirection.forward || notification.metrics.pixels <= 60) {
                if (!ref.read(bottomNavVisibilityProvider)) {
                  ref.read(bottomNavVisibilityProvider.notifier).state = true;
                }
              }
            }
            return false;
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
    ),
  );
  }
}

/// Blinkit signature header with 10-15 Mins Delivery Badge & Location bar.
class _GiftsAppBar extends StatelessWidget {
  const _GiftsAppBar();

  static const Color _blinkitGreen = Color(0xFF0C831F);
  static const Color _blinkitYellow = Color(0xFFF7C400);

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: ZopiqSpacing.pageGutter,
      toolbarHeight: 72,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.card_giftcard_rounded, color: _blinkitGreen, size: 26),
              const SizedBox(width: 8),
              Text(
                'Gifts',
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Handcrafted & curated things to gift someone',
            style: t.bodySmall?.copyWith(
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Blinkit Hero Carousel & Search Bar with festive gradient backdrop.
class _HeroGiftBanner extends StatelessWidget {
  const _HeroGiftBanner({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.xs,
        ),
        child: Column(
          children: <Widget>[
            // Blinkit Festive Hero Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? <Color>[
                          const Color(0xFF154326),
                          const Color(0xFF1E1E24),
                        ]
                      : <Color>[
                          const Color(0xFF0C831F),
                          const Color(0xFF15A030),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _blinkitGreen.withValues(alpha: isDark ? 0.3 : 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7C400),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'STUDIO CURATED',
                          style: t.labelSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.verified_rounded,
                              size: 11,
                              color: Color(0xFFFFD700),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Verified Artisans',
                              style: t.labelSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Make Every Moment Special 🎁',
                              style: t.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Handmade gifts, artisan boxes & custom notes',
                              style: t.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Search Bar
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search handcrafted gifts, candles, frames...',
                hintStyle: t.bodyMedium?.copyWith(
                  color: zc.textMuted,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _blinkitGreen,
                  size: 22,
                ),
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
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: _blinkitGreen,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blinkit Category Rail with Icon Avatars.
class _CategoryFilterRail extends StatelessWidget {
  const _CategoryFilterRail({
    required this.categories,
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  IconData _getCategoryIcon(String category) {
    final String catLower = category.toLowerCase();
    if (catLower.contains('home') || catLower.contains('decor')) {
      return Icons.home_max_rounded;
    } else if (catLower.contains('candle') || catLower.contains('scent')) {
      return Icons.wb_incandescent_rounded;
    } else if (catLower.contains('choc') || catLower.contains('sweet')) {
      return Icons.cake_rounded;
    } else if (catLower.contains('frame') || catLower.contains('art')) {
      return Icons.photo_size_select_actual_rounded;
    }
    return Icons.grid_view_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeader(title: 'Browse By Category'),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.pageGutter,
            ),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final String cat = categories[index];
              final bool isSelected = cat == selectedCategory;

              return GestureDetector(
                onTap: () => onSelectCategory(cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _blinkitGreen
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected
                          ? _blinkitGreen
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFE2E8F0)),
                      width: 1.2,
                    ),
                    boxShadow: isSelected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: _blinkitGreen.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (cat != 'All') ...<Widget>[
                        Icon(
                          _getCategoryIcon(cat),
                          size: 14,
                          color: isSelected ? Colors.white : _blinkitGreen,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        cat,
                        style: t.labelSmall?.copyWith(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF334155)),
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Blinkit Partner Gift Studios Rail.
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
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
              ),
              itemCount: shops.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
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

/// Blinkit Storefront Gift Grid.
///
/// A [ConsumerWidget] only so that opening an item can slide the shell's pills
/// out of the way — the sheet itself takes the ref, so the grid must have one.
class _GiftGrid extends ConsumerWidget {
  const _GiftGrid({required this.items});

  final List<GiftItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final double width = constraints.crossAxisExtent;
        final int crossAxisCount = width > 900 ? 4 : (width > 550 ? 3 : 2);
        final double childAspectRatio = width < 400 ? 0.60 : 0.64;

        return SliverMainAxisGroup(
          slivers: <Widget>[
            const SliverToBoxAdapter(child: _SectionHeader(title: 'All Gifts')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.pageGutter,
                0,
                ZopiqSpacing.pageGutter,
                ZopiqSpacing.lg,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    return RepaintBoundary(
                      child: GiftItemCard(
                        item: items[i],
                        onTap: () => showGiftItemSheet(context, ref, items[i]),
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

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: _blinkitGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

