import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';

/// Order confirmation — the one screen in the app that exists purely to make
/// someone feel good. It reads the receipt from [lastPlacedOrderProvider] rather
/// than route `extra`, so it survives router rebuilds. The ETA here is a promise,
/// not a status: "Track this order" opens the order itself, where the timeline is
/// live.
class OrderSuccessPage extends ConsumerWidget {
  const OrderSuccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final PlacedOrder? order = ref.watch(lastPlacedOrderProvider);

    // A cold deep link to /checkout/success has no order to show.
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('No recent order', style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Browse restaurants',
                  expand: false,
                  onPressed: () => context.goNamed(Routes.home),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            children: <Widget>[
              const Spacer(),
              const _SuccessMark(),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqReveal(
                index: 1,
                child: Column(
                  children: <Widget>[
                    Text('Order placed!', style: t.headlineSmall),
                    const SizedBox(height: ZopiqSpacing.xs),
                    Text(
                      'Order ${order.id} · ${order.restaurantName}',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              // The ETA is the single fact the customer actually wants off this
              // screen, so it is the biggest thing on it after the tick.
              ZopiqReveal(index: 2, child: _EtaBadge(minutes: order.etaMinutes)),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqReveal(
                index: 3,
                child: ZopiqCard(
                  elevated: false,
                  child: Column(
                    children: <Widget>[
                      _DetailRow(
                        icon: Icons.location_on_rounded,
                        text: 'Delivering to ${order.deliveryTo}',
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      _DetailRow(
                        icon: Icons.payments_outlined,
                        text: order.paymentMethod == PaymentMethod.cod
                            ? 'Pay ₹${order.total} in cash on delivery'
                            : 'Paid ₹${order.total} · ${order.paymentId}',
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              ZopiqReveal(
                index: 4,
                child: Column(
                  children: <Widget>[
                    ZopiqButton(
                      label: 'Track this order',
                      variant: ZopiqButtonVariant.cta,
                      // Straight to the order, which is where tracking lives —
                      // the button finally does what it says. `go`, not `push`:
                      // nothing above the shell should survive a completed
                      // checkout — the cart is empty and there is nothing to go
                      // back *to*. `go` rebuilds the stack from the route tree,
                      // so `/orders` sits underneath and Back lands on the list.
                      onPressed: () => context.goNamed(
                        Routes.orderDetail,
                        pathParameters: <String, String>{'id': order.id},
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    TextButton(
                      onPressed: () => context.goNamed(Routes.home),
                      child: const Text('Back to home'),
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

/// The tick: a ring that expands and fades out behind a mark that scales in.
///
/// One shot, transforms and opacity only, and it *settles* — an ambient pulse
/// here would look expensive and would mean `pumpAndSettle` never returned in
/// any test that reaches this screen.
class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: ZopiqCurves.emphasized,
      builder: (BuildContext context, double t, Widget? child) {
        return SizedBox.square(
          dimension: 128,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The halo. Grows past the mark and fades as it goes, so the
              // moment reads as a burst rather than a badge appearing.
              Opacity(
                opacity: (1 - t) * 0.35,
                child: Transform.scale(
                  scale: 0.6 + t * 0.9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: zc.veg,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 112),
                  ),
                ),
              ),
              Transform.scale(
                // A hint of overshoot, so it lands rather than arrives.
                scale: (0.4 + t * 0.68).clamp(0.0, 1.0) * (1 + (1 - t) * 0.06),
                child: child,
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: zc.veg.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, size: 56, color: zc.veg),
      ),
    );
  }
}

class _EtaBadge extends StatelessWidget {
  const _EtaBadge({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.lg,
        vertical: ZopiqSpacing.md,
      ),
      decoration: BoxDecoration(
        color: zc.primary.withValues(alpha: 0.10),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.delivery_dining_rounded, color: zc.primary, size: 22),
          const SizedBox(width: ZopiqSpacing.sm),
          Text(
            'Arriving in about $minutes min',
            style: t.titleSmall?.copyWith(
              color: zc.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: zc.primary),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(child: Text(text, style: t.bodyMedium)),
      ],
    );
  }
}
