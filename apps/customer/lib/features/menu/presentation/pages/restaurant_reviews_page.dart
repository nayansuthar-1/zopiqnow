import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

/// Every review a restaurant has, on a page of its own.
///
/// It used to be three reviews inlined into the menu with a "see all" sheet
/// behind them — opinions wedged between the vitals and the food, on a screen
/// somebody opened to order. The menu now carries the average and a button, and
/// this is what the button opens: a page, with a back arrow, that a customer
/// reaches when they have decided they want to read them.
class RestaurantReviewsPage extends ConsumerWidget {
  const RestaurantReviewsPage({required this.restaurantId, super.key});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final Color surface = Theme.of(context).colorScheme.surface;
    final AsyncValue<List<RestaurantReview>> reviews = ref.watch(
      restaurantReviewsProvider(restaurantId),
    );

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Reviews',
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: reviews.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object error, _) => _ReviewsMessage(
          icon: Icons.wifi_off_rounded,
          message: 'We couldn\'t load the reviews. Please try again.',
          onRetry: () =>
              ref.invalidate(restaurantReviewsProvider(restaurantId)),
        ),
        data: (List<RestaurantReview> all) {
          if (all.isEmpty) {
            return const _ReviewsMessage(
              icon: Icons.rate_review_outlined,
              message: 'Nobody has reviewed this kitchen yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.pageGutter,
              0,
              ZopiqSpacing.pageGutter,
              ZopiqSpacing.xxl,
            ),
            // One extra row at the top: the summary the menu's button came from,
            // restated here so the page stands on its own.
            itemCount: all.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: ZopiqSpacing.md),
            itemBuilder: (BuildContext context, int i) => i == 0
                ? _ReviewsSummary(restaurantId: restaurantId, shown: all.length)
                : ReviewCard(review: all[i - 1]),
          );
        },
      ),
    );
  }
}

/// The average, the count, and the kitchen it belongs to.
class _ReviewsSummary extends ConsumerWidget {
  const _ReviewsSummary({required this.restaurantId, required this.shown});

  final String restaurantId;

  /// How many reviews the list below actually holds. Shown when the restaurant
  /// row is not there to give a rating count — and it differs from that count
  /// anyway: a rating without words is a rating, not a review.
  final int shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Restaurant? r = ref
        .watch(restaurantByIdProvider(restaurantId))
        .valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: Row(
        children: <Widget>[
          if (r != null && r.ratingCount > 0) ...<Widget>[
            RatingBadge(rating: r.rating),
            const SizedBox(width: ZopiqSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (r != null)
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  '$shown review${shown == 1 ? '' : 's'}'
                  '${r != null && r.ratingCount > 0 ? ' · ${r.ratingCount} rating${r.ratingCount == 1 ? '' : 's'}' : ''}',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One review: the stars, who left it, when, and what they said.
///
/// Public because the reviews page is no longer the only thing that draws a
/// review — the menu's rating row links here, and a second surface reading the
/// same rows should not draw them a second way.
class ReviewCard extends StatelessWidget {
  const ReviewCard({required this.review, super.key});

  final RestaurantReview review;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: zc.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int star = 1; star <= 5; star++)
                Icon(
                  star <= review.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 15,
                  color: star <= review.rating ? zc.rating : zc.textMuted,
                ),
              const SizedBox(width: ZopiqSpacing.sm),
              Expanded(
                child: Text(
                  review.reviewer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _ago(review.createdAt),
                style: t.labelSmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
          if (review.comment case final String comment) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.sm),
            Text(comment, style: t.bodyMedium),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inHours < 24) return 'today';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

/// The green score chip. Shared with the menu's rating row so the number reads
/// identically on both screens.
class RatingBadge extends StatelessWidget {
  const RatingBadge({required this.rating, super.key});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: zc.veg,
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: ZopiqPalette.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.xxs),
          const Icon(Icons.star_rounded, size: 16, color: ZopiqPalette.white),
        ],
      ),
    );
  }
}

/// Empty, or failed. One shape for both, because both are a glyph, a sentence
/// and — when retrying could help — a button.
class _ReviewsMessage extends StatelessWidget {
  const _ReviewsMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: zc.textMuted),
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
