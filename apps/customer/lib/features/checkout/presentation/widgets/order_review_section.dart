import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_review.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/rate_order_sheet.dart';

/// The rating prompt on a delivered order, in one of three renderings:
///
///   * **nothing at all** — the order is not reviewable (still cooking, or the
///     fortnight has passed). No greyed-out button, no "you can no longer rate
///     this": an expired prompt is noise on a receipt somebody opened to check
///     what they paid.
///   * **a prompt** — five tappable stars and a line of copy.
///   * **what they said** — the rating already given, with a Change button
///     while the hour lasts.
///
/// Which one shows is decided by `order_review_state`, never here. See
/// [OrderReviewState].
class OrderReviewSection extends ConsumerWidget {
  const OrderReviewSection({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final OrderReviewState state =
        ref.watch(orderReviewStateProvider(orderId)).valueOrNull ??
        OrderReviewState.none;
    final OrderReview? mine = ref.watch(myOrderReviewProvider(orderId)).valueOrNull;

    // Nothing to offer and nothing already said. Render nothing — including
    // while the two reads are still in flight, so the receipt does not jump.
    if (!state.canReview && mine == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          mine == null ? 'RATE THIS ORDER' : 'YOUR RATING',
          style: t.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
            color: isDark ? Colors.white54 : const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 12),

        if (mine == null)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'How was the food? Your rating is what the next customer sees.',
                  style: t.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFF555555),
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // The stars *are* the button. A customer who taps four opens the
              // sheet with four already picked, so the commonest rating costs
              // one tap and a confirm rather than three taps and a hunt.
              for (int star = 1; star <= 5; star++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  constraints: const BoxConstraints(),
                  tooltip: 'Rate $star',
                  icon: Icon(
                    Icons.star_outline_rounded,
                    size: 26,
                    color: zc.rating,
                  ),
                  onPressed: () => showRateOrderSheet(
                    context,
                    orderId: orderId,
                    state: state,
                    initialFood: star,
                  ),
                ),
            ],
          )
        else
          Row(
            children: <Widget>[
              _Stars(value: mine.foodRating),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mine.comment ?? 'Rated ${mine.foodRating} out of 5',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFF555555),
                    fontSize: 12.5,
                  ),
                ),
              ),
              // The row that disappears an hour after the first rating, because
              // the row underneath it stops accepting writes at the same moment
              // (0062). The button is the warning; the trigger is the rule.
              if (mine.isEditable)
                TextButton(
                  onPressed: () => showRateOrderSheet(
                    context,
                    orderId: orderId,
                    state: state,
                    existing: mine,
                  ),
                  child: const Text('Change'),
                ),
            ],
          ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int star = 1; star <= 5; star++)
          Icon(
            star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: star <= value ? zc.rating : zc.textMuted,
          ),
      ],
    );
  }
}
