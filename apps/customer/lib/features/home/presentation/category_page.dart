import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/core/l10n/strings.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/cart_fab.dart';
import 'package:zopiqnow/features/home/domain/entities/dish_suggestion.dart';
import 'package:zopiqnow/features/home/domain/entities/food_category.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/dish_providers.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/dish_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/food_category_rail.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_filter_chips.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';
import 'package:zopiqnow/features/home/presentation/widgets/section_header.dart';

/// One dish category — everything nearby that serves it.
///
/// **Why a page and not a search.** Tapping "Pizza" used to type the word into
/// the search field and hand over to the search screen. That worked, and it was
/// the wrong shape: search runs an `ilike` across every restaurant on the
/// platform, so the results included kitchens that do not deliver here, and the
/// rail vanished the moment you arrived — leaving no way to say "actually,
/// burgers" without going back first.
///
/// So the rail comes along. Switching categories rebuilds this page in place
/// rather than pushing another copy of it, which keeps the back button meaning
/// "return to Home" however many categories have been tried.
///
/// No hero: this screen is for someone who has already decided what they want to
/// eat, and a campaign banner is an argument with that decision.
class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({required this.categoryId, super.key});

  final String categoryId;

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  late String _selectedId = widget.categoryId;

  void _open(FoodCategory category) {
    if (category.id == 'view_more' || category.id == _selectedId) return;
    setState(() => _selectedId = category.id);
  }

  @override
  Widget build(BuildContext context) {
    // Both rails, so a category reachable only through "View more" still has a
    // page — and so the tile stays visible after it is chosen.
    final List<FoodCategory> categories = <FoodCategory>[
      ...ref.watch(foodCategoriesProvider),
      ...ref.watch(moreFoodCategoriesProvider),
    ]..removeWhere((FoodCategory c) => c.id == 'view_more');

    // Veg mode can hide the category that is open. Falling back to the first
    // remaining one beats rendering an empty screen with nothing selected.
    final FoodCategory selected = categories.firstWhere(
      (FoodCategory c) => c.id == _selectedId,
      orElse: () => categories.first,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchPill(
          onTap: () => context.pushNamed(Routes.search),
        ),
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoryRailDelegate(
              categories: categories,
              selectedId: selected.id,
              onTapCategory: _open,
            ),
          ),
          const SliverPersistentHeader(
            pinned: true,
            delegate: HomeFilterChipsHeader(),
          ),
          // The whole category, not its label: matching needs the tile's kind
          // and its spelling aliases as well as the word under the picture. See
          // `category_matching.dart`.
          _RecommendedSection(category: selected),
          _CategoryListSection(category: selected),
        ],
      ),
      // This page is outside the shell, so it has no bottom bar — and the dish
      // rail above lets a dish be added without leaving it. Without this the
      // only way to the cart was back to Home first.
      floatingActionButton: const CartFab(),
    );
  }
}

/// Looks like the Home search field and does the same thing. Not a real input:
/// typing belongs to the search screen, and two fields that both accept text
/// would leave the user wondering which one is searching.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.only(right: ZopiqSpacing.pageGutter),
      child: InkWell(
        borderRadius: ZopiqRadii.rMd,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: ZopiqRadii.rMd,
            border: Border.all(color: zc.divider),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded, size: 20, color: zc.primary),
              const SizedBox(width: ZopiqSpacing.sm),
              Expanded(
                child: Text(
                  'Restaurant name or a dish',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRailDelegate extends SliverPersistentHeaderDelegate {
  const _CategoryRailDelegate({
    required this.categories,
    required this.selectedId,
    required this.onTapCategory,
  });

  final List<FoodCategory> categories;
  final String selectedId;
  final ValueChanged<FoodCategory> onTapCategory;

  @override
  double get minExtent => FoodCategoryRail.railHeight;
  @override
  double get maxExtent => FoodCategoryRail.railHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: context.zc.divider)),
      ),
      child: FoodCategoryRail(
        categories: categories,
        selectedId: selectedId,
        onTapCategory: onTapCategory,
      ),
    );
  }

  @override
  bool shouldRebuild(_CategoryRailDelegate old) =>
      old.selectedId != selectedId || old.categories.length != categories.length;
}

/// "Recommended for you", narrowed to the open category — the same dish rail
/// Home shows, over dishes that are actually [label].
///
/// A category page is for someone who has already decided what they want to eat,
/// so recommending them a kitchen was answering a question they had not asked.
class _RecommendedSection extends ConsumerWidget {
  const _RecommendedSection({required this.category});

  final FoodCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DishSuggestion> dishes =
        ref.watch(categoryDishesProvider(category)).valueOrNull ??
        const <DishSuggestion>[];
    // Silent when empty: the list below already owns the empty state, and two
    // "nothing here" messages on one screen is one too many.
    if (dishes.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: SectionHeader(title: context.l10n.homeRecommendedForYou),
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

class _CategoryListSection extends ConsumerWidget {
  const _CategoryListSection({required this.category});

  /// Both the matching key and the caption key: [FoodCategory.label] stays
  /// English and does the matching, [FoodCategory.id] looks the display name up.
  /// See `AppStrings.categoryName` for why they must not be the same string.
  final FoodCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Restaurant>> feed = ref.watch(
      categoryRestaurantsProvider(category),
    );
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
              : context.l10n.homeConnectionError,
          onRetry: () => ref.invalidate(nearbyRestaurantsProvider),
        ),
      ),
      data: (List<Restaurant> restaurants) {
        if (restaurants.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: HomeNoMatchesView(
              message: context.l10n.homeNoCategoryNearby(
                context.l10n.categoryName(category.id, category.label),
              ),
            ),
          );
        }
        return SliverMainAxisGroup(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
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
                    color: context.zc.textMuted,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                ZopiqSpacing.lg,
                0,
                ZopiqSpacing.lg,
                // Clear of the cart button, which floats over this list.
                ZopiqSpacing.lg + CartFab.clearance(ref),
              ),
              sliver: SliverList.separated(
                itemCount: restaurants.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ZopiqSpacing.lg),
                itemBuilder: (BuildContext context, int i) => RepaintBoundary(
                  child: RestaurantCard(
                    restaurant: restaurants[i],
                    photos: photos[restaurants[i].id] ?? const <String>[],
                    onTap: () => _openMenu(context, restaurants[i]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

void _openMenu(BuildContext context, Restaurant restaurant) {
  context.pushNamed(
    Routes.menu,
    pathParameters: <String, String>{'id': restaurant.id},
  );
}
