import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/features/reviews/domain/entities/vendor_review.dart';
import 'package:zopiq_vendor/features/reviews/presentation/providers/reviews_providers.dart';

/// What customers are saying — the tile on the More hub that used to say
/// "coming soon" and mean it.
///
/// The room is deliberately read-only. There is no reply box, no report button
/// and no way to hide a review: a kitchen that could answer publicly is a
/// moderation product, and one that could hide a 1★ is not running a rating
/// system at all. The one thing the vendor can do with a bad review is cook
/// better, which is the point.
class ReviewsPage extends ConsumerWidget {
  const ReviewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VendorReview>> reviews = ref.watch(reviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews'), centerTitle: true),
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref
            ..invalidate(reviewsProvider)
            ..invalidate(reviewSummaryProvider);
          await ref.read(reviewsProvider.future);
        },
        child: reviews.when(
          loading: () => const Center(child: ZopiqLoader()),
          error: (Object _, StackTrace _) => _ErrorBody(
            onRetry: () {
              ref
                ..invalidate(reviewsProvider)
                ..invalidate(reviewSummaryProvider);
            },
          ),
          data: (List<VendorReview> list) => ListView(
            padding: const EdgeInsets.only(
              top: ZopiqSpacing.md,
              bottom: ZopiqSpacing.xxl,
            ),
            children: <Widget>[
              const VendorFadeSlide(child: _SummaryCard()),
              if (list.isEmpty)
                const VendorFadeSlide(
                  delay: Duration(milliseconds: 80),
                  child: _EmptyBody(),
                )
              else
                for (int i = 0; i < list.length; i++)
                  VendorFadeSlide(
                    delay: Duration(milliseconds: 60 + i * 40),
                    child: _ReviewTile(review: list[i]),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final VendorReviewSummary s =
        ref.watch(reviewSummaryProvider).valueOrNull ??
        VendorReviewSummary.empty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        0,
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    // A dash, not "0.0". A kitchen nobody has rated yet has no
                    // score — it does not have the worst possible one.
                    s.isEmpty ? '—' : s.rating.toStringAsFixed(1),
                    style: t.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.star_rounded, color: zc.rating, size: 24),
                ],
              ),
              Text(
                s.isEmpty
                    ? 'No ratings yet'
                    : '${s.ratingCount} rating${s.ratingCount == 1 ? '' : 's'}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
          const SizedBox(width: ZopiqSpacing.xl),
          Expanded(
            child: Column(
              children: <Widget>[
                for (int star = 5; star >= 1; star--)
                  _StarBar(
                    star: star,
                    count: s.stars[star] ?? 0,
                    total: s.ratingCount,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the histogram. The bar is a proportion of the *total*, not of the
/// biggest bucket — a shop with 40 fives and 2 ones should look like one.
class _StarBar extends StatelessWidget {
  const _StarBar({required this.star, required this.count, required this.total});

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 12,
            child: Text(
              '$star',
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total,
                minHeight: 6,
                backgroundColor: zc.textMuted.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(zc.rating),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final VendorReview review;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.lg,
        vertical: ZopiqSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Pill(rating: review.foodRating),
              const SizedBox(width: ZopiqSpacing.sm),
              Expanded(
                child: Text(
                  review.orderId,
                  style: t.labelMedium?.copyWith(
                    color: zc.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _ago(review.createdAt),
                style: t.labelSmall?.copyWith(color: zc.textMuted),
              ),
            ],
          ),
          if (review.comment case final String comment) ...<Widget>[
            const SizedBox(height: 6),
            Text(comment, style: t.bodyMedium),
          ],
          // The delivery's score, when the customer gave one. Labelled as the
          // rider's, because the kitchen is not being marked on it.
          if (review.riderRating case final int riderRating) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Delivery rated $riderRating★',
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
          ],
          const SizedBox(height: ZopiqSpacing.sm),
          Divider(height: 1, color: zc.textMuted.withValues(alpha: 0.15)),
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    // Green at 4 and up, amber at 3, red below. The same three-way split every
    // food app uses, because it is the one an owner reads without a legend.
    final Color colour = rating >= 4
        ? zc.veg
        : rating == 3
        ? zc.rating
        : Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$rating',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 12, color: Colors.white),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(ZopiqSpacing.xxl),
      child: Column(
        children: <Widget>[
          Icon(Icons.reviews_outlined, size: 44, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.md),
          Text(
            'No reviews yet',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'A customer can rate an order for a fortnight after it arrives. '
            'You\'ll get a notification when one does.',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'We couldn\'t load your reviews.',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            const SizedBox(height: ZopiqSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
