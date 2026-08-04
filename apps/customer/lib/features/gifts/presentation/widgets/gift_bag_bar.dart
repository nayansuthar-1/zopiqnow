import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';

/// The docked "you have things in a bag" bar, and the only route to the bag.
///
/// Renders nothing when the bag is empty — a persistent empty bar is a
/// permanent tax on a screen somebody is browsing. The same shape as the food
/// [CartBar], deliberately: two carts that behaved differently would be two
/// things to learn.
class GiftBagBar extends ConsumerWidget {
  const GiftBagBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GiftCart bag = ref.watch(giftCartProvider);
    if (bag.isEmpty) return const SizedBox.shrink();

    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        child: Material(
          color: zc.primary,
          borderRadius: ZopiqRadii.rMd,
          child: InkWell(
            borderRadius: ZopiqRadii.rMd,
            onTap: () => context.pushNamed(Routes.giftBag),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.lg,
                vertical: ZopiqSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Text(
                      '${bag.itemCount} gift${bag.itemCount == 1 ? '' : 's'} '
                      '· ₹${bag.subtotal}',
                      style: t.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'View bag',
                    style: t.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
