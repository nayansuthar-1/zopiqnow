import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// The gift bag: what is about to be bought, and the way to buy it.
///
/// It shows a subtotal and **says GST is added at checkout** rather than
/// guessing at it. The rate is per item (0096) and the rounding is per slab, so
/// a number computed here would be an estimate that disagrees with the receipt
/// on a bag spanning two rates — and a total that changes between two screens is
/// worse than a total that only appears on one.
class GiftBagPage extends ConsumerWidget {
  const GiftBagPage({required this.onCheckout, required this.onBrowse, super.key});

  final VoidCallback onCheckout;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GiftCart bag = ref.watch(giftCartProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        // The same fallback the cart and the orders list use: pop if there is
        // something to pop, and otherwise go somewhere real.
        leading: BackButton(
          onPressed: () =>
              Navigator.of(context).canPop() ? Navigator.of(context).pop() : onBrowse(),
        ),
        title: const Text('Gift bag'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (bag.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(giftCartProvider.notifier).clear(),
              child: const Text('Empty'),
            ),
        ],
      ),
      body: bag.isEmpty
          ? _EmptyBag(onBrowse: onBrowse)
          : ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
                vertical: ZopiqSpacing.md,
              ),
              children: <Widget>[
                if (bag.shopName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
                    child: Text(
                      'From ${bag.shopName}',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                for (final GiftCartLine line in bag.lines) ...<Widget>[
                  _BagLine(line: line),
                  const SizedBox(height: ZopiqSpacing.md),
                ],
                const SizedBox(height: ZopiqSpacing.sm),
                Divider(color: zc.divider, height: 1),
                const SizedBox(height: ZopiqSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('Subtotal', style: t.bodyLarge),
                    ),
                    Text(
                      '₹${bag.subtotal}',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  'GST is added at checkout, and delivery by the Zopiqnow team '
                  'is free.',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
      bottomNavigationBar: bag.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
                child: ZopiqButton(
                  label: 'Checkout · ${bag.itemCount} item'
                      '${bag.itemCount == 1 ? '' : 's'}',
                  variant: ZopiqButtonVariant.cta,
                  onPressed: onCheckout,
                ),
              ),
            ),
    );
  }
}

class _BagLine extends ConsumerWidget {
  const _BagLine({required this.line});

  final GiftCartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final GiftCartNotifier bag = ref.read(giftCartProvider.notifier);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: ZopiqRadii.rMd,
          child: SizedBox(
            width: 64,
            height: 64,
            child: GiftImage(
              url: line.item.imageUrl,
              seed: line.item.id,
              icon: Icons.card_giftcard_rounded,
              iconSize: 24,
            ),
          ),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                line.item.name,
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '₹${line.item.price} each',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Row(
                children: <Widget>[
                  _StepButton(
                    icon: Icons.remove_rounded,
                    onTap: () => bag.setQuantity(
                      line.item.id,
                      line.quantity - 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.md,
                    ),
                    child: Text(
                      '${line.quantity}',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add_rounded,
                    onTap: () => bag.setQuantity(
                      line.item.id,
                      line.quantity + 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text(
          '₹${line.lineTotal}',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rSm,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: zc.divider),
          borderRadius: ZopiqRadii.rSm,
        ),
        child: Icon(icon, size: 16, color: zc.primary),
      ),
    );
  }
}

class _EmptyBag extends StatelessWidget {
  const _EmptyBag({required this.onBrowse});

  final VoidCallback onBrowse;

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
            Icon(
              Icons.card_giftcard_rounded,
              size: 56,
              color: zc.textMuted,
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('Your gift bag is empty', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Everything you add from a gift shop shows up here.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: 'Browse gifts',
              expand: false,
              onPressed: onBrowse,
            ),
          ],
        ),
      ),
    );
  }
}
