import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/food_category_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_app_bar.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_filter_chips.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';
import 'package:zopiqnow/features/home/presentation/widgets/section_header.dart';
import 'package:zopiqnow/features/home/presentation/widgets/top_chains_rail.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/address_picker_sheet.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';

/// Opens a restaurant's menu. Shared by the list cards and the top-chains rail.
void _openMenu(BuildContext context, Restaurant restaurant) {
  context.pushNamed(
    Routes.menu,
    pathParameters: <String, String>{'id': restaurant.id},
  );
}

/// Customer Home — restaurant discovery. The top is Zomato's home (a
/// full-bleed brand hero carrying the location/search header and a campaign
/// banner); everything below is Swiggy's layout: the dish-category rail, a
/// top-chains rail, then the filterable restaurant list.
///
/// Every section is its own sliver so the scroll view only builds and paints
/// what is on screen — the rails do not cost anything once scrolled past.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  AnimationController? _filterAnimCtrl;
  Animation<double>? _filterAnim;

  @override
  void initState() {
    super.initState();
    _initAnim();
    _scroll.addListener(_onScroll);
  }

  void _initAnim() {
    _filterAnimCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _filterAnim ??= CurvedAnimation(
      parent: _filterAnimCtrl!,
      curve: Curves.easeInOutCubic,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final bool atTop = _scroll.offset <= 10;
    final bool isVisible = ref.read(bottomNavVisibilityProvider);
    if (atTop != isVisible) {
      ref.read(bottomNavVisibilityProvider.notifier).state = atTop;
    }

    final bool shouldHideFilters = _scroll.offset > 400; // Half of Top Chains
    if (_filterAnimCtrl != null) {
      if (shouldHideFilters &&
          _filterAnimCtrl!.status != AnimationStatus.dismissed &&
          _filterAnimCtrl!.status != AnimationStatus.reverse) {
        _filterAnimCtrl!.reverse();
      } else if (!shouldHideFilters &&
          _filterAnimCtrl!.status != AnimationStatus.completed &&
          _filterAnimCtrl!.status != AnimationStatus.forward) {
        _filterAnimCtrl!.forward();
      }
    }
  }

  @override
  void dispose() {
    _filterAnimCtrl?.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// The hero's "Order now": advance the feed by roughly one viewport, which
  /// lands at the restaurant list without hardcoding any section heights.
  void _scrollTowardsRestaurants() {
    if (!_scroll.hasClients) return;
    final ScrollPosition p = _scroll.position;
    _scroll.animateTo(
      (p.pixels + p.viewportDimension * 0.9).clamp(0, p.maxScrollExtent),
      duration: ZopiqDurations.slow,
      curve: ZopiqCurves.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<FoodCategory> categories = ref.watch(foodCategoriesProvider);
    final Address? address = ref.watch(selectedAddressProvider);

    // Full-bleed: no top SafeArea, so the hero carousel bleeds behind the
    // status bar. The app bar insets its own content by the real top padding,
    // and — because it owns the status-bar area — the pinned filter chips still
    // stop below the clock rather than under it.
    final double topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        // The spinner drops over the hero, so it must not be hero-colored.
        color: ZopiqPalette.primaryDeep,
        backgroundColor: ZopiqPalette.white,
        // Sit the spinner just below the status bar, clear of the search pill.
        edgeOffset: topInset + ZopiqSpacing.sm,
        displacement: 40,
        onRefresh: () => ref.refresh(nearbyRestaurantsProvider.future),
        child: CustomScrollView(
          controller: _scroll,
          // Clamping (not bouncing): a pull-to-refresh drags only the
          // spinner, never the hero. The content stays put on overscroll.
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: <Widget>[
            HomeSliverAppBar(
              // Null on a first run. Inventing a default city would be
              // a lie about where we deliver — ask instead.
              address: address?.shortDisplay ?? 'Set delivery location',
              onTapLocation: () => showAddressPicker(context),
              onTapSearch: () => context.goNamed(Routes.search),
              onTapProfile: () => context.pushNamed(Routes.account),
              onTapCta: _scrollTowardsRestaurants,
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _FoodCategoryRailDelegate(categories),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.lg)),
            AnimatedBuilder(
              animation: _filterAnim ?? const AlwaysStoppedAnimation(1.0),
              builder: (BuildContext context, Widget? child) {
                _initAnim(); // Ensure init on hot reload
                return SliverPersistentHeader(
                  pinned: true,
                  delegate: HomeFilterChipsHeader(
                    heightFactor: _filterAnim!.value,
                  ),
                );
              },
            ),
            const _TopChainsSection(),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.lg)),
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Restaurants with online food delivery',
              ),
            ),
            const _RestaurantListSection(),
          ],
        ),
      ),
    );
  }
}

/// The top-chains rail. Silent while the feed loads or fails — the restaurant
/// list below already owns the shimmer and the retry, and duplicating either
/// here would put two spinners (or two errors) on one screen.
class _TopChainsSection extends ConsumerWidget {
  const _TopChainsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Restaurant> top =
        ref.watch(topRatedRestaurantsProvider).valueOrNull ??
        const <Restaurant>[];
    if (top.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverMainAxisGroup(
      slivers: <Widget>[
        const SliverToBoxAdapter(
          child: SectionHeader(title: 'Recommended for you'),
        ),
        SliverToBoxAdapter(
          child: TopChainsRail(
            restaurants: top,
            onTapRestaurant: (Restaurant r) => _openMenu(context, r),
          ),
        ),
      ],
    );
  }
}

class _RestaurantListSection extends ConsumerWidget {
  const _RestaurantListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Restaurant>> feed = ref.watch(
      filteredRestaurantsProvider,
    );

    return feed.when(
      loading: () => const SliverPadding(
        padding: EdgeInsets.all(ZopiqSpacing.lg),
        sliver: SliverToBoxAdapter(child: RestaurantListSkeleton()),
      ),
      error: (Object error, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: HomeErrorView(
          message: error is RestaurantLoadFailure
              ? error.message
              : 'Please check your connection and try again.',
          onRetry: () => ref.invalidate(nearbyRestaurantsProvider),
        ),
      ),
      data: (List<Restaurant> restaurants) {
        if (restaurants.isEmpty) {
          // An empty *filtered* feed is a different problem from an empty area.
          final bool filtersActive = ref
              .read(homeFiltersProvider)
              .hasActiveToggle;
          return SliverFillRemaining(
            hasScrollBody: false,
            child: filtersActive
                ? const HomeNoMatchesView()
                : const HomeEmptyView(),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.all(ZopiqSpacing.lg),
          sliver: SliverList.separated(
            itemCount: restaurants.length,
            separatorBuilder: (_, _) => const SizedBox(height: ZopiqSpacing.lg),
            itemBuilder: (BuildContext context, int i) => RepaintBoundary(
              child: RestaurantCard(
                restaurant: restaurants[i],
                onTap: () => _openMenu(context, restaurants[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FoodCategoryRailDelegate extends SliverPersistentHeaderDelegate {
  _FoodCategoryRailDelegate(this.categories);
  final List<FoodCategory> categories;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: FoodCategoryRail(
        categories: categories,
        onTapCategory: (FoodCategory _) {},
      ),
    );
  }

  @override
  double get maxExtent => FoodCategoryRail.railHeight;

  @override
  double get minExtent => FoodCategoryRail.railHeight;

  @override
  bool shouldRebuild(covariant _FoodCategoryRailDelegate oldDelegate) {
    return categories != oldDelegate.categories;
  }
}
