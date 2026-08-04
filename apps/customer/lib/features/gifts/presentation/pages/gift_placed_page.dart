import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';

/// The acknowledgement. The one screen in the Gifts flow that exists purely to
/// tell somebody their money went somewhere and something is happening.
///
/// It reads the receipt from [lastGiftOrderProvider] rather than route `extra`,
/// so a router rebuild cannot blank it — the same reasoning as the food
/// confirmation, and it matters more here: a gift has no ETA and no live
/// tracking, so this screen and the order screen are the *only* two places the
/// customer is ever told anything.
///
/// It is honest about what happens next. No invented delivery estimate: a gift
/// is packed and couriered by the Zopiqnow team on no promised clock (0096), and
/// a made-up "arriving Tuesday" is the one number that would be a lie.
class GiftPlacedPage extends ConsumerWidget {
  const GiftPlacedPage({
    required this.onTrack,
    required this.onBrowse,
    super.key,
  });

  final void Function(String orderId) onTrack;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final GiftOrder? order = ref.watch(lastGiftOrderProvider);

    // A cold link to this route has no receipt to show.
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('No recent gift order', style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Browse gifts',
                  expand: false,
                  onPressed: onBrowse,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            children: <Widget>[
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: zc.veg.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  size: 42,
                  color: zc.veg,
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqReveal(
                index: 1,
                child: Column(
                  children: <Widget>[
                    Text('Gift ordered!', style: t.headlineSmall),
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      '${order.id}${order.shopName.isEmpty ? '' : ' · ${order.shopName}'}',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              ZopiqReveal(
                index: 2,
                child: ZopiqCard(
                  elevated: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Row(
                        icon: Icons.payments_outlined,
                        text: 'Paid ₹${order.total}',
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      _Row(
                        icon: Icons.location_on_rounded,
                        text: 'Sending to ${order.deliveryTo}',
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      // The whole of what happens next, in one sentence, with
                      // nothing invented in it.
                      const _Row(
                        icon: Icons.local_shipping_outlined,
                        text: 'Our team will pack this and hand it to a '
                            'courier. You\'ll see the courier and the tracking '
                            'number here as soon as it goes out.',
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),
              ZopiqReveal(
                index: 3,
                child: Column(
                  children: <Widget>[
                    ZopiqButton(
                      label: 'Track this gift',
                      variant: ZopiqButtonVariant.cta,
                      onPressed: () => onTrack(order.id),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    TextButton(
                      onPressed: onBrowse,
                      child: const Text('Back to gifts'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: zc.textMuted),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(child: Text(text, style: t.bodyMedium)),
      ],
    );
  }
}
