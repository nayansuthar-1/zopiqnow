import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';

/// Order confirmation. Reads the receipt from [lastPlacedOrderProvider] rather
/// than route `extra`, so it survives router rebuilds; live tracking replaces
/// the static ETA in Step 8.
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
              // One-shot scale-in; settles, so tests can pumpAndSettle.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.4, end: 1),
                duration: ZopiqDurations.slow,
                curve: ZopiqCurves.emphasized,
                builder: (_, double scale, Widget? child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: zc.veg.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, size: 56, color: zc.veg),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              Text('Order placed!', style: t.headlineSmall),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Order ${order.id} · ${order.restaurantName}',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqCard(
                elevated: false,
                child: Column(
                  children: <Widget>[
                    _DetailRow(
                      icon: Icons.schedule_rounded,
                      text: 'Arriving in about ${order.etaMinutes} min',
                    ),
                    const SizedBox(height: ZopiqSpacing.md),
                    _DetailRow(
                      icon: Icons.location_on_rounded,
                      text: 'Delivering to ${order.deliveryTo}',
                    ),
                    const SizedBox(height: ZopiqSpacing.md),
                    _DetailRow(
                      icon: Icons.payments_outlined,
                      text: order.paymentMethod == PaymentMethod.cod
                          ? 'Pay ₹${order.total} in cash on delivery'
                          : 'Paid ₹${order.total}',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ZopiqButton(
                label: 'Back to home',
                variant: ZopiqButtonVariant.cta,
                onPressed: () => context.goNamed(Routes.home),
              ),
            ],
          ),
        ),
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
