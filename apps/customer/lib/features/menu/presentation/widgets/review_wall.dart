import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/menu/domain/entities/restaurant_review.dart';
import 'package:zopiqnow/features/menu/presentation/providers/menu_providers.dart';

/// What people said about this restaurant — the section that makes the number
/// at the top of the page mean something.
///
/// Renders **nothing at all** until there is at least one review, including
/// while the read is in flight. A "No reviews yet" placeholder above a menu is a
/// blank the customer has to scroll past on the way to the food; a heading that
/// appears once there is something under it is not.
///
/// Three, not all of them, with the rest a page away — this is a menu screen,
/// and a customer scrolling to order should meet dishes before opinions.
class ReviewWall extends ConsumerWidget {
  const ReviewWall({required this.restaurantId, super.key});

  final String restaurantId;

  static const int _preview = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    final List<RestaurantReview> all =
        ref.watch(restaurantReviewsProvider(restaurantId)).valueOrNull ??
        const <RestaurantReview>[];
    if (all.isEmpty) return const SizedBox.shrink();

    final List<RestaurantReview> shown = all.take(_preview).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'What people say',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          for (final RestaurantReview review in shown)
            _ReviewCard(review: review),
          if (all.length > _preview)
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _AllReviewsSheet(reviews: all),
              ),
              child: Text('See all ${all.length} reviews'),
            ),
          const SizedBox(height: ZopiqSpacing.sm),
          Divider(height: 1, color: zc.textMuted.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}

class _AllReviewsSheet extends StatelessWidget {
  const _AllReviewsSheet({required this.reviews});

  final List<RestaurantReview> reviews;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        children: <Widget>[
          Text(
            'Reviews',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          for (final RestaurantReview review in reviews)
            _ReviewCard(review: review),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final RestaurantReview review;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.reviewer,
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
            const SizedBox(height: 4),
            Text(comment, style: t.bodySmall),
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
