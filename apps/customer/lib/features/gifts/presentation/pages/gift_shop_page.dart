import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/domain/repositories/gift_repository.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_card.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_item_sheet.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_status_views.dart';

/// A single gift shop's storefront: its cover and tagline up top, then its
/// products grouped by shelf (the `category`), in the vendor's chosen order.
///
/// Resolves from the id alone so a cold link works without the Gifts feed ever
/// having loaded.
class GiftShopPage extends ConsumerWidget {
  const GiftShopPage({required this.shopId, super.key});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GiftShop> shop = ref.watch(giftShopByIdProvider(shopId));
    final AsyncValue<List<GiftItem>> items = ref.watch(
      giftItemsByShopProvider(shopId),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: shop.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (Object error, _) => GiftErrorView(
          message: error is GiftShopNotFound
              ? error.message
              : error is GiftLoadFailure
              ? error.message
              : 'Please check your connection and try again.',
          onRetry: () => ref.invalidate(giftShopByIdProvider(shopId)),
        ),
        data: (GiftShop s) => CustomScrollView(
          slivers: <Widget>[
            _ShopHeader(shop: s),
            _ShopDescription(description: s.description),
            items.when(
              loading: () => const SliverToBoxAdapter(child: GiftGridSkeleton()),
              error: (Object error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: GiftErrorView(
                  message: 'We couldn\'t load this shop\'s gifts.',
                  onRetry: () =>
                      ref.invalidate(giftItemsByShopProvider(shopId)),
                ),
              ),
              data: (List<GiftItem> list) => _ShopItems(items: list),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: ZopiqSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.shop});

  final GiftShop shop;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GiftImage(
              url: shop.imageUrl,
              seed: shop.id,
              icon: Icons.storefront_rounded,
              iconSize: 64,
            ),
            // Scrim so the back button and title stay legible over any photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.black54, Colors.transparent, Colors.black54],
                  stops: <double>[0, 0.4, 1],
                ),
              ),
            ),
            Positioned(
              left: ZopiqSpacing.lg,
              right: ZopiqSpacing.lg,
              bottom: ZopiqSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    shop.name,
                    style: t.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    shop.tagline,
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  if (shop.rating != null) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.sm),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.star_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: ZopiqSpacing.xxs),
                        Text(
                          '${shop.rating!.toStringAsFixed(1)}  ·  ${shop.ratingCount}+ ratings',
                          style: t.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shop's blurb, rendered as its own sliver beneath the header. Kept off the
/// [SliverAppBar.bottom] so it scrolls away with the content rather than pinning.
class _ShopDescription extends StatelessWidget {
  const _ShopDescription({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    if (description.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZopiqSpacing.lg,
          ZopiqSpacing.lg,
          ZopiqSpacing.lg,
          0,
        ),
        child: Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.zc.textMuted,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ShopItems extends StatelessWidget {
  const _ShopItems({required this.items});

  final List<GiftItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: GiftEmptyView(),
      );
    }

    // Group into shelves, preserving the query's order (category_rank, item_rank)
    // — the vendor's merchandising, not a re-sort.
    final List<String> shelves = <String>[];
    final Map<String, List<GiftItem>> byShelf = <String, List<GiftItem>>{};
    for (final GiftItem item in items) {
      final List<GiftItem> bucket =
          byShelf.putIfAbsent(item.category, () {
            shelves.add(item.category);
            return <GiftItem>[];
          });
      bucket.add(item);
    }

    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final double width = constraints.crossAxisExtent;
        final int crossAxisCount = width > 900 ? 4 : (width > 550 ? 3 : 2);
        final double childAspectRatio = width < 400 ? 0.62 : 0.66;

        return SliverMainAxisGroup(
          slivers: <Widget>[
            for (final String shelf in shelves) ...<Widget>[
              SliverToBoxAdapter(child: _ShelfHeader(title: shelf)),
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
                      final GiftItem item = byShelf[shelf]![i];
                      return RepaintBoundary(
                        child: GiftItemCard(
                          item: item,
                          onTap: () => showGiftItemSheet(context, item),
                        ),
                      );
                    },
                    childCount: byShelf[shelf]!.length,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
