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

/// A single gift shop's storefront page:
/// Features Blinkit studio header with verified artisan badge, rating pill,
/// shop description card, and products organized by shelf.
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

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 230,
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
            // Multi-layered Scrim
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black54,
                    Colors.black26,
                    Colors.black87,
                  ],
                  stops: <double>[0.0, 0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Badges Row
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.workspace_premium_rounded,
                              size: 12,
                              color: Color(0xFFFFD700),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'VERIFIED STUDIO',
                              style: t.labelSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    shop.name,
                    style: t.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shop.tagline,
                    style: t.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                  if (shop.rating != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _blinkitGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            shop.rating!.toStringAsFixed(1),
                            style: t.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${shop.ratingCount}+ ratings',
                            style: t.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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

/// The shop's blurb with clean icon callout.
class _ShopDescription extends StatelessWidget {
  const _ShopDescription({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    if (description.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Color(0xFF0C831F),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    height: 1.4,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
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
        final double childAspectRatio = width < 400 ? 0.60 : 0.64;

        return SliverMainAxisGroup(
          slivers: <Widget>[
            for (final String shelf in shelves) ...<Widget>[
              SliverToBoxAdapter(child: _ShelfHeader(title: shelf)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
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

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: _blinkitGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

