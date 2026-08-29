import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/cart_bar.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/beverage_upsell.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_filter_bar.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_header.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

/// Restaurant detail — vitals plus the categorised menu, with the sticky cart
/// bar docked at the bottom.
class MenuPage extends ConsumerWidget {
  const MenuPage({
    required this.restaurantId,
    required this.onViewCart,
    super.key,
  });

  final String restaurantId;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Restaurant> restaurant = ref.watch(
      restaurantByIdProvider(restaurantId),
    );

    return Scaffold(
      // The back arrow lives in [MenuSliverAppBar], which only exists once the
      // restaurant has arrived — so while this is loading, and *permanently* if
      // the id is not a restaurant, the screen had no way out at all. Android
      // hid that behind the system Back; iOS has none, and `RestaurantNotFound`
      // offers no retry either, so it was a dead end. A plain bar here, and none
      // once the sliver one takes over.
      appBar: restaurant.hasValue
          ? null
          : AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
            ),
      body: restaurant.when(
        loading: () => const _MenuLoading(),
        error: (Object error, _) => _MenuError(
          message: switch (error) {
            RestaurantNotFound(:final String message) => message,
            RestaurantLoadFailure(:final String message) => message,
            _ => 'Please check your connection and try again.',
          },
          // A missing restaurant will never appear on retry; only offer the
          // action that can actually work.
          onRetry: error is RestaurantNotFound
              ? null
              : () => ref.invalidate(restaurantByIdProvider(restaurantId)),
        ),
        data: (Restaurant r) => _MenuBody(restaurant: r),
      ),
      // The drinks are offered here, on the way to the cart, and not on every
      // dish added. `onceOnly` keeps it to one prompt per basket, and
      // `offerABeverage` returns immediately on an empty cart — so tapping CART
      // with nothing in it just opens the cart.
      //
      // Before the sheet rather than after: once the cart page is open the
      // customer is reading a bill, and a drinks sheet over a bill is an
      // interruption rather than an offer.
      bottomNavigationBar: CartBar(
        onViewCart: () async {
          final Cart cart = ref.read(cartProvider);
          final String? id = cart.restaurantId;
          final String? name = cart.restaurantName;
          if (id != null && name != null) {
            await offerABeverage(
              context,
              ref,
              restaurantId: id,
              restaurantName: name,
              onceOnly: true,
            );
          }
          if (context.mounted) onViewCart();
        },
      ),
    );
  }
}

class _MenuBody extends ConsumerWidget {
  const _MenuBody({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MenuCategory>> menu = ref.watch(
      filteredMenuProvider(restaurant.id),
    );

    return Stack(
      children: <Widget>[
        CustomScrollView(
          slivers: <Widget>[
            MenuTopBar(restaurant: restaurant),
            SliverToBoxAdapter(child: MenuVitals(restaurant: restaurant)),
            SliverToBoxAdapter(
              child: MenuOffersStrip(restaurantId: restaurant.id),
            ),
            // What people said (0062) is no longer inlined here. The vitals
            // carry the average and an "All reviews" button, and the reviews
            // themselves live on `RestaurantReviewsPage` — a customer scrolling
            // to order should meet dishes, not opinions.
            if (!restaurant.acceptingOrders)
              SliverToBoxAdapter(
                child: _ClosedBanner(reason: restaurant.pauseReason),
              ),
            const MenuFilterBar(),
            const SliverToBoxAdapter(child: _FocusedCategoryBanner()),
            menu.when(
              loading: () => const SliverToBoxAdapter(child: _MenuLoading()),
              error: (Object error, _) => SliverToBoxAdapter(
                child: _MenuError(
                  message: error is MenuLoadFailure
                      ? error.message
                      : 'Please check your connection and try again.',
                  onRetry: () => ref.invalidate(menuProvider(restaurant.id)),
                ),
              ),
              data: (List<MenuCategory> categories) {
                if (categories.isEmpty) {
                  return const SliverToBoxAdapter(child: _NothingMatches());
                }
                return SliverList.builder(
                  itemCount: categories.length,
                  itemBuilder: (BuildContext context, int i) => _MenuSection(
                    category: categories[i],
                    restaurant: restaurant,
                  ),
                );
              },
            ),
            // No drinks rail here. One stood at the foot of this list for a
            // day, as the route to a drink-only order; the instruction is that
            // the seeded drinks are not on the menu at all, and the foot of the
            // menu is still the menu. They are offered on the two screens where
            // a drink is an addition to a meal — the strip after a dish goes in
            // the cart, and the rail on the cart page itself.
            //
            // Breathing room so neither the cart bar nor the Menu button ever
            // covers the last dish.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
        Positioned(
          right: ZopiqSpacing.pageGutter,
          bottom: ZopiqSpacing.lg,
          child: _MenuJumpButton(restaurantId: restaurant.id),
        ),
      ],
    );
  }
}

/// The floating "Menu" button — the way out of a hundred-dish scroll.
class _MenuJumpButton extends ConsumerWidget {
  const _MenuJumpButton({required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The whole menu rather than the filtered one: this is how a customer
    // reaches a section, so it has to list the sections a filter has hidden.
    //
    // `browsableMenuProvider` and not `menuProvider`, though — the seeded
    // bottled drinks are not hidden by a switch the customer can flick, so a
    // "Beverages" entry pointing at nothing but them is a control that does
    // nothing when tapped.
    final List<MenuCategory> categories =
        ref.watch(browsableMenuProvider(restaurantId)).valueOrNull ??
        const <MenuCategory>[];
    // One section is not a menu to navigate.
    if (categories.length < 2) return const SizedBox.shrink();

    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // The button inverts against the page rather than being painted a fixed
    // colour. It used to be `zc.textStrong` with hardcoded white text — which is
    // a near-black chip in light mode and a near-*white* one in dark, where the
    // white label sat on top of it and the button read as a blank rounded
    // rectangle. Both halves have to flip together, so they are derived from one
    // brightness check rather than set independently.
    final Color background = isDark
        ? const Color(0xFFF2F3F5)
        : const Color(0xFF1C1D1F);
    final Color foreground = isDark
        ? const Color(0xFF1C1D1F)
        : ZopiqPalette.white;

    return Material(
      color: background,
      borderRadius: ZopiqRadii.rMd,
      elevation: 6,
      // A dark chip on a dark page needs its own edge to sit on; without it the
      // elevation shadow is the only thing separating the two and it disappears
      // against anything but white.
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.3),
      child: InkWell(
        borderRadius: ZopiqRadii.rMd,
        onTap: () async {
          final int? picked = await showMenuJumpSheet(
            context,
            categories: categories,
          );
          if (picked == null) return;
          ref.read(focusedCategoryProvider.notifier).state =
              categories[picked].title;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.lg,
            vertical: ZopiqSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.restaurant_menu_rounded,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: ZopiqSpacing.sm),
              Text(
                'Menu',
                style: t.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Says which section is being shown alone, and how to stop.
///
/// Without it the customer is looking at a menu that has silently lost sixteen
/// of its seventeen sections, which reads as a broken restaurant rather than as
/// a choice they made.
class _FocusedCategoryBanner extends ConsumerWidget {
  const _FocusedCategoryBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? focused = ref.watch(focusedCategoryProvider);
    if (focused == null) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Showing $focused only',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(focusedCategoryProvider.notifier).state = null,
            child: const Text('Show full menu'),
          ),
        ],
      ),
    );
  }
}

/// One section, with a header that folds it away.
///
/// Collapsing matters more the longer the menu is: seventeen sections of pizza
/// variants is a lot of scrolling to get past something you are not eating
/// today. Expanded by default, because a menu that arrives closed is a menu the
/// customer has to open before they can read it.
class _MenuSection extends StatefulWidget {
  const _MenuSection({required this.category, required this.restaurant});

  final MenuCategory category;
  final Restaurant restaurant;

  @override
  State<_MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<_MenuSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: ZopiqSpacing.xl),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${widget.category.title} (${widget.category.items.length})',
                    style: t.headlineMedium,
                  ),
                ),
                // Points the way it will move: down to open, up to close.
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: zc.textMuted,
                ),
              ],
            ),
          ),
          if (_expanded)
            for (final MenuItem item in widget.category.items)
              MenuItemTile(
                key: ValueKey<String>(item.id),
                item: item,
                restaurantId: widget.restaurant.id,
                restaurantName: widget.restaurant.name,
                enabled: widget.restaurant.acceptingOrders,
              )
          else
            // A closed section still shows the divider the open one ends on, so
            // two collapsed headings do not run together into one block of text.
            Divider(height: ZopiqSpacing.xl, color: zc.divider),
        ],
      ),
    );
  }
}

/// Shown under the vitals when the kitchen has paused orders. It explains why
/// every ADD below it is greyed out — without it, a disabled button is just a
/// bug the customer can see.
class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({this.reason = ''});

  /// The kitchen's own words, when it gave any (migration 0068). Preferred over
  /// the platform's sentence because "short on staff" tells a customer whether
  /// to wait ten minutes or eat somewhere else, and "paused orders" does not.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        decoration: BoxDecoration(
          color: zc.nonVeg.withValues(alpha: 0.10),
          borderRadius: ZopiqRadii.rMd,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.no_meals_rounded, color: zc.nonVeg, size: 22),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Closed for now',
                    style: t.titleSmall?.copyWith(
                      color: zc.nonVeg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    reason.isNotEmpty
                        ? '$reason. You can browse the menu, but you can\'t '
                              'order right now.'
                        : 'This restaurant has paused orders. You can browse '
                              'the menu, but you can\'t order right now.',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuLoading extends StatelessWidget {
  const _MenuLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(ZopiqSpacing.lg),
      child: ZopiqShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ZopiqSkeletonBox(height: 140, borderRadius: ZopiqRadii.rMd),
            SizedBox(height: ZopiqSpacing.lg),
            ZopiqSkeletonBox(width: 180, height: 22),
            SizedBox(height: ZopiqSpacing.lg),
            ZopiqSkeletonBox(height: 96, borderRadius: ZopiqRadii.rMd),
            SizedBox(height: ZopiqSpacing.lg),
            ZopiqSkeletonBox(height: 96, borderRadius: ZopiqRadii.rMd),
          ],
        ),
      ),
    );
  }
}

class _MenuError extends StatelessWidget {
  const _MenuError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.storefront_outlined, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(
              message,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: onRetry!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nothing survived the filters. One message for all of them, because the
/// customer can see which ones are on — they are pinned to the top of the
/// screen — and a message that named them would be reading the chips back.
class _NothingMatches extends ConsumerWidget {
  const _NothingMatches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.all(ZopiqSpacing.xxl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 48, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.lg),
          Text(
            'Nothing on this menu matches.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: zc.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ZopiqSpacing.lg),
          ZopiqButton(
            label: 'Clear filters',
            expand: false,
            variant: ZopiqButtonVariant.outline,
            onPressed: () {
              // `toggle` is the only thing the veg notifier exposes, and that is
              // deliberate on its side — nothing else should be able to set a
              // dietary filter to an arbitrary value.
              if (ref.read(vegOnlyProvider)) {
                ref.read(vegOnlyProvider.notifier).toggle();
              }
              ref.read(bestsellersOnlyProvider.notifier).state = false;
              ref.read(menuSearchProvider.notifier).state = '';
              ref.read(focusedCategoryProvider.notifier).state = null;
            },
          ),
        ],
      ),
    );
  }
}
