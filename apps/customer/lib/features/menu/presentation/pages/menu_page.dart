import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/widgets/cart_bar.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_header.dart';
import 'package:zopiqnow/features/menu/presentation/widgets/menu_item_tile.dart';

/// Restaurant detail — vitals plus the categorised menu, with the sticky cart
/// bar docked at the bottom.
class MenuPage extends ConsumerWidget {
  const MenuPage({required this.restaurantId, required this.onViewCart, super.key});

  final String restaurantId;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Restaurant> restaurant =
        ref.watch(restaurantByIdProvider(restaurantId));

    return Scaffold(
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
      bottomNavigationBar: CartBar(onViewCart: onViewCart),
    );
  }
}

class _MenuBody extends ConsumerWidget {
  const _MenuBody({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MenuCategory>> menu =
        ref.watch(filteredMenuProvider(restaurant.id));

    return CustomScrollView(
      slivers: <Widget>[
        MenuSliverAppBar(restaurant: restaurant),
        SliverToBoxAdapter(child: MenuVitals(restaurant: restaurant)),
        const SliverToBoxAdapter(child: _VegOnlyToggle()),
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
            if (categories.isEmpty) return const SliverToBoxAdapter(child: _NoVegItems());
            return SliverList.builder(
              itemCount: categories.length,
              itemBuilder: (BuildContext context, int i) => _MenuSection(
                category: categories[i],
                restaurant: restaurant,
              ),
            );
          },
        ),
        // Breathing room so the cart bar never covers the last dish.
        const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.xxl)),
      ],
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.category, required this.restaurant});

  final MenuCategory category;
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            '${category.title} (${category.items.length})',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          for (final MenuItem item in category.items)
            MenuItemTile(
              key: ValueKey<String>(item.id),
              item: item,
              restaurantId: restaurant.id,
              restaurantName: restaurant.name,
            ),
        ],
      ),
    );
  }
}

class _VegOnlyToggle extends ConsumerWidget {
  const _VegOnlyToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool vegOnly = ref.watch(vegOnlyProvider);
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: Row(
        children: <Widget>[
          Switch.adaptive(
            value: vegOnly,
            activeTrackColor: zc.veg,
            onChanged: (_) => ref.read(vegOnlyProvider.notifier).toggle(),
          ),
          const SizedBox(width: ZopiqSpacing.sm),
          Text('Veg only', style: Theme.of(context).textTheme.titleSmall),
        ],
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

class _NoVegItems extends StatelessWidget {
  const _NoVegItems();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.all(ZopiqSpacing.xxl),
      child: Column(
        children: <Widget>[
          Icon(Icons.eco_outlined, size: 48, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.lg),
          Text(
            'No vegetarian dishes on this menu.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: zc.textMuted,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
