import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/hero_slide.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/dish_providers.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/dish_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/food_category_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_app_bar.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_filter_chips.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/more_categories_sheet.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';
import 'package:zopiqnow/features/home/presentation/widgets/section_header.dart';
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
/// banner); everything below is Swiggy's layout: the dish-category rail, a rail
/// of recommended dishes, then the filterable restaurant list.
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
  /// Lives in [homeScrollControllerProvider], not here — the shell returns this
  /// feed to the top on system Back and cannot reach a controller owned by a
  /// widget it does not build. Riverpod disposes it, so this page must not.
  late final ScrollController _scroll = ref.read(homeScrollControllerProvider);
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
    // Change threshold from 10 to 400 to hide when the recommended rail is in
    // the middle
    final bool atTop = _scroll.offset <= 400;
    final bool isVisible = ref.read(bottomNavVisibilityProvider);
    if (atTop != isVisible) {
      ref.read(bottomNavVisibilityProvider.notifier).state = atTop;
    }

    final bool shouldHideFilters =
        _scroll.offset > 400; // Half of the recommended rail
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
    // Listener off, controller left alone: the provider owns it, and disposing
    // it here would leave the shell holding a dead controller the next time
    // Home is built.
    _scroll.removeListener(_onScroll);
    super.dispose();
  }

  /// A published slide's own destination. The database has already checked that
  /// it is one of a closed set and that it exists (migration 0053), so this only
  /// has to decide *how* to go there — and the two answers are different.
  ///
  /// A restaurant is pushed, like every other route to a menu, so Back returns
  /// to Home. A tab is `go`, because pushing one on top of Home would leave the
  /// bottom bar highlighting a tab the user is not on.
  void _openHeroTarget(String target) {
    if (target.startsWith('/restaurant/')) {
      context.push(target);
    } else {
      context.go(target);
    }
  }

  /// A tap on the "What's on your mind?" rail.
  ///
  /// Two destinations, because the rail has two kinds of tile. "View More" opens
  /// [showMoreCategoriesSheet], which is the screen built for it. Every other
  /// tile opens [CategoryPage].
  ///
  /// It used to type the label into the search field and hand over to search.
  /// That was wrong twice: search queries every restaurant on the platform, so
  /// the results included kitchens that do not deliver here, and arriving on the
  /// search screen left no rail to switch categories with. The category page
  /// filters the *nearby* feed and brings the rail along.
  ///
  /// Pushed, not `go`: it sits outside the shell, so a `go` would leave it with
  /// no bottom bar and no back arrow — a screen with no way out.
  void _openCategory(FoodCategory category) {
    if (category.id == 'view_more') {
      showMoreCategoriesSheet(context);
      return;
    }
    context.pushNamed(
      Routes.category,
      pathParameters: <String, String>{'id': category.id},
    );
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

    // `valueOrNull`, so loading and failure are both "no campaign running" and
    // the carousel draws the art it ships with. A hero is the first thing on the
    // first screen: it has no business showing a spinner, and it certainly has
    // no business showing an error about a marketing banner.
    final List<HeroSlide> heroSlides =
        ref.watch(heroSlidesProvider).valueOrNull ?? const <HeroSlide>[];

    // Full-bleed: no top SafeArea, so the hero carousel bleeds behind the
    // status bar. The app bar insets its own content by the real top padding,
    // and — because it owns the status-bar area — the pinned filter chips still
    // stop below the clock rather than under it.
    final double topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator.adaptive(
        // The spinner drops over the hero, so it must not be hero-colored.
        color: ZopiqPalette.primaryDeep,
        backgroundColor: ZopiqPalette.white,
        // Sit the spinner just below the status bar, clear of the search pill.
        edgeOffset: topInset + ZopiqSpacing.sm,
        displacement: 40,
        onRefresh: () {
          // The hero's cache invalidation (see `heroSlidesProvider`). Not
          // awaited: the spinner belongs to the feed, and a slow banner fetch
          // must not hold it spinning over a list that has already arrived.
          ref.invalidate(heroSlidesProvider);
          return ref.refresh(nearbyRestaurantsProvider.future);
        },
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
              heroSlides: heroSlides,
              // Wrapped, because this is the one address picker opened from a
              // screen the pills are actually on — the checkout ones sit on
              // pushed routes that already cover the shell.
              onTapLocation: () =>
                  withBottomNavHidden(ref, () => showAddressPicker(context)),
              // Pushed, not `go` — the same rule `_openCategory` follows and for
              // the same reason. Search sits outside the shell, so a `go`
              // replaces the stack and leaves it with neither a bottom bar nor a
              // back arrow. On Android that was survivable; on iOS there is no
              // system Back, so the search pill was a one-way door.
              onTapSearch: () => context.pushNamed(Routes.search),
              onTapProfile: () => context.pushNamed(Routes.account),
              onTapCta: _scrollTowardsRestaurants,
              onOpenHeroTarget: _openHeroTarget,
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _FoodCategoryRailDelegate(categories, _openCategory),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.xs)),
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
            const _RecommendedDishesSection(),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.lg)),
            const _RestaurantCountHeader(),
            const _RestaurantListSection(),
          ],
        ),
      ),
    );
  }
}

/// "Recommended for you" — dishes, not restaurants.
///
/// Ranked against this phone's recent searches (see [recommendedDishesProvider]),
/// so the section answers "what should I eat?" rather than "whose menu should I
/// go read?". Tapping a card opens the dish's menu; the card's own ADD button
/// means the customer need not go there at all.
///
/// Silent while the feed loads or fails — the restaurant list below already owns
/// the shimmer and the retry, and duplicating either here would put two spinners
/// (or two errors) on one screen.
class _RecommendedDishesSection extends ConsumerWidget {
  const _RecommendedDishesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DishSuggestion> dishes =
        ref.watch(recommendedDishesProvider).valueOrNull ??
        const <DishSuggestion>[];
    if (dishes.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: <Widget>[
        const SliverToBoxAdapter(
          child: SectionHeader(title: 'Recommended for you'),
        ),
        SliverToBoxAdapter(
          child: DishRail(
            dishes: dishes,
            onOpenDish: (DishSuggestion d) => _openMenu(context, d.restaurant),
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
    // Empty until the photo request lands, which costs one rebuild and never a
    // loading state — a card without its strip is a finished card.
    final Map<String, List<String>> photos = ref.watch(cardPhotosProvider);

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
                photos: photos[restaurants[i].id] ?? const <String>[],
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
  _FoodCategoryRailDelegate(this.categories, this.onTapCategory);
  final List<FoodCategory> categories;
  final ValueChanged<FoodCategory> onTapCategory;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: FoodCategoryRail(
        categories: categories,
        onTapCategory: onTapCategory,
      ),
    );
  }

  @override
  double get maxExtent => FoodCategoryRail.railHeight;

  @override
  double get minExtent => FoodCategoryRail.railHeight;

  @override
  bool shouldRebuild(covariant _FoodCategoryRailDelegate oldDelegate) => true;
}

class _RestaurantCountHeader extends ConsumerWidget {
  const _RestaurantCountHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Restaurant>> feed = ref.watch(filteredRestaurantsProvider);

    return SliverToBoxAdapter(
      child: feed.when(
        data: (List<Restaurant> restaurants) {
          if (restaurants.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.lg,
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.md,
            ),
            child: Text(
              '${restaurants.length} RESTAURANTS DELIVERING TO YOU',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}
