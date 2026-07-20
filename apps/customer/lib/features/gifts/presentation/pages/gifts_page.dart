import 'package:flutter/material.dart';
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

/// The Gifts tab — a second storefront beside food. Not restaurants, not dishes:
/// handcrafted and curated things one person buys to give another. Sellers are
/// dedicated gift shops, browsed here as a rail up top with a grid of every
/// product below.
///
/// Browse-only for now — tapping a product opens a detail sheet, not a cart. A
/// gift cart and checkout are a later task.
class GiftsPage extends ConsumerWidget {
  const GiftsPage({required this.onOpenShop, super.key});

  /// Navigates to a shop's storefront page. Injected so the page stays free of
  /// go_router — the router owns the wiring.
  final void Function(GiftShop shop) onOpenShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            _GiftShopsRail(onOpenShop: onOpenShop),
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
                if (list.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GiftEmptyView(),
                  );
                }
                return _GiftGrid(items: list);
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
              Icon(Icons.card_giftcard_rounded, color: zc.primaryDeep, size: 24),
              const SizedBox(width: ZopiqSpacing.sm),
              Text(
                'Gifts',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 32),
            child: Text(
              'Handcrafted things to gift someone',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ),
        ],
      ),
      toolbarHeight: 64,
    );
  }
}

/// The gift-shops rail. Silent while it loads or fails — the item grid below
/// already owns the shimmer and the retry, and a second of either on one screen
/// reads as broken.
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
          const _SectionHeader(title: 'Gift shops'),
          SizedBox(
            height: 190,
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
    return SliverMainAxisGroup(
      slivers: <Widget>[
        const SliverToBoxAdapter(child: _SectionHeader(title: 'All gifts')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            ZopiqSpacing.lg,
            0,
            ZopiqSpacing.lg,
            ZopiqSpacing.lg,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: ZopiqSpacing.lg,
              crossAxisSpacing: ZopiqSpacing.lg,
              childAspectRatio: 0.68,
            ),
            delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
              return RepaintBoundary(
                child: GiftItemCard(
                  item: items[i],
                  onTap: () => showGiftItemSheet(context, items[i]),
                ),
              );
            }, childCount: items.length),
          ),
        ),
      ],
    );
  }
}

/// Uppercase section title, matching Home's rail headings.
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
        ZopiqSpacing.md,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
