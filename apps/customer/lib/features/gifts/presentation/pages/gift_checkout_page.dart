import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_outcome.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_cart.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_cart_providers.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/address_picker_sheet.dart';

/// Where a gift is paid for.
///
/// Deliberately thinner than the food checkout, and every omission is a decision
/// rather than a gap: no coupons, no fee breakdown, no ETA, no tip. A gift is
/// couriered by the Zopiqnow team on no promised clock (0096), and inventing a
/// delivery estimate for a parcel nobody has picked up would be the one number
/// on this screen that was made up.
///
/// The payment goes through the **same gateway as food** — Razorpay when it is
/// configured, the mock behind it while it is not. There is no second payment
/// path to keep honest.
class GiftCheckoutPage extends ConsumerStatefulWidget {
  const GiftCheckoutPage({
    required this.onPlaced,
    required this.onBrowse,
    super.key,
  });

  /// Called once the order exists, with its receipt already parked in
  /// [lastGiftOrderProvider].
  final VoidCallback onPlaced;
  final VoidCallback onBrowse;

  @override
  ConsumerState<GiftCheckoutPage> createState() => _GiftCheckoutPageState();
}

class _GiftCheckoutPageState extends ConsumerState<GiftCheckoutPage> {
  bool _placing = false;
  String? _failure;

  /// One key per checkout attempt, reused on every retry of it. Regenerated only
  /// when the customer starts a genuinely new attempt — which is what makes a
  /// lost response safe to retry without buying the gift twice (0086, 0096).
  String? _idempotencyKey;

  Future<void> _pay(GiftCart bag, Address address, GiftQuote quote) async {
    if (_placing) return;
    setState(() {
      _placing = true;
      _failure = null;
    });

    _idempotencyKey ??=
        'gift-${DateTime.now().microsecondsSinceEpoch}-${bag.shopId}';

    try {
      // The gateway is asked for the **quoted** total, tax included. It used to
      // be asked for `bag.subtotal`, which is items only — so the customer was
      // charged the pre-tax figure while the order recorded the tax-inclusive
      // one, and the GST on every gift sold was booked as collected and never
      // was (0112). The quote comes from the same function that prices the
      // order, so the two numbers cannot disagree.
      final PaymentOutcome outcome = await ref
          .read(paymentGatewayProvider)
          .pay(
            amount: quote.total,
            description: 'Zopiqnow gift · ${bag.shopName}',
          );

      if (!mounted) return;

      switch (outcome) {
        case PaymentCancelled():
          setState(() => _placing = false);
          return;
        case PaymentFailed(:final String message):
          setState(() {
            _placing = false;
            _failure = message;
          });
          return;
        case PaymentSucceeded(:final String paymentId):
          final AuthState auth = ref.read(authControllerProvider);
          final GiftOrder order = await ref
              .read(giftOrderDataSourceProvider)
              .placeOrder(
                shopId: bag.shopId,
                items: bag.toOrderItems(),
                // The number a courier would ring. Not an identity — the buyer
                // is whoever the JWT says, exactly as `place_order` decides it.
                userPhone: auth is AuthSignedIn ? (auth.user.phone ?? '') : '',
                deliveryTo: address.shortDisplay,
                paymentId: paymentId,
                idempotencyKey: _idempotencyKey,
              );

          if (!mounted) return;
          ref.read(lastGiftOrderProvider.notifier).set(order);
          ref.read(giftCartProvider.notifier).clear();
          // The list is stale the moment this order exists.
          ref.invalidate(giftOrdersProvider);
          widget.onPlaced();
      }
    } on GiftOrderFailure catch (failure) {
      if (mounted) {
        setState(() {
          _placing = false;
          _failure = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GiftCart bag = ref.watch(giftCartProvider);
    final Address? address = ref.watch(selectedAddressProvider);
    final AsyncValue<GiftQuote?> quote = ref.watch(giftQuoteProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    if (bag.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Your gift bag is empty', style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Browse gifts',
                  expand: false,
                  onPressed: widget.onBrowse,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Checkout'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          Text(
            'SENDING TO',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: zc.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          ZopiqCard(
            elevated: false,
            child: InkWell(
              onTap: () => showAddressPicker(context),
              borderRadius: ZopiqRadii.rMd,
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.md),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.location_on_rounded, color: zc.primary),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Text(
                        address?.shortDisplay ?? 'Choose an address',
                        style: t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: address == null ? zc.textMuted : null,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: zc.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xl),

          Text(
            'YOUR GIFTS',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: zc.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          for (final GiftCartLine line in bag.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${line.quantity} × ${line.item.name}',
                      style: t.bodyMedium,
                    ),
                  ),
                  Text('₹${line.lineTotal}', style: t.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: ZopiqSpacing.sm),
          Divider(color: zc.divider, height: 1),
          const SizedBox(height: ZopiqSpacing.md),
          _BillRow(label: 'Subtotal', amount: bag.subtotal),
          // Fetched, not computed. The rate is per item and the rounding is per
          // slab (0096), so these are the service's figures — the same ones the
          // receipt will carry, because the same function produced both (0112).
          switch (quote) {
            AsyncData<GiftQuote?>(value: final GiftQuote q) => Column(
              children: <Widget>[
                const SizedBox(height: ZopiqSpacing.xs),
                if (q.deliveryFee > 0)
                  _BillRow(label: 'Delivery', amount: q.deliveryFee),
                _BillRow(label: 'GST', amount: q.taxes),
                const SizedBox(height: ZopiqSpacing.sm),
                Divider(color: zc.divider, height: 1),
                const SizedBox(height: ZopiqSpacing.sm),
                _BillRow(label: 'To pay', amount: q.total, strong: true),
              ],
            ),
            AsyncError<GiftQuote?>(:final Object error) => Padding(
              padding: const EdgeInsets.only(top: ZopiqSpacing.sm),
              child: Text(
                error is GiftOrderFailure
                    ? error.message
                    : 'We couldn\'t work out the total just now.',
                style: t.bodySmall?.copyWith(color: zc.nonVeg),
              ),
            ),
            _ => Padding(
              padding: const EdgeInsets.only(top: ZopiqSpacing.sm),
              child: Text(
                'Working out the total…',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
            ),
          },
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            'Delivery by the Zopiqnow team is free.',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          // Said before the money moves, not discovered afterwards on the order
          // screen. A gift order is final once it is placed (0116), and a rule
          // the customer only meets when they try to undo something is the rule
          // that generates the complaint rather than preventing it.
          Text(
            'Gift orders can\'t be cancelled once placed.',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),

          if (_failure case final String failure) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.lg),
            Text(failure, style: t.bodyMedium?.copyWith(color: zc.nonVeg)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          child: ZopiqButton(
            label: switch (quote) {
              AsyncData<GiftQuote?>(value: final GiftQuote q) =>
                'Pay ₹${q.total}',
              _ => 'Pay',
            },
            variant: ZopiqButtonVariant.cta,
            isLoading: _placing || quote.isLoading,
            // No address, no order. The server refuses one anyway — this is the
            // wall being where the finger is. And no quote, no order either:
            // the amount charged has to be a number somebody was shown, not a
            // guess made while it was still arriving.
            onPressed:
                address == null || quote.valueOrNull == null
                    ? null
                    : () => _pay(bag, address, quote.value!),
          ),
        ),
      ),
    );
  }
}

/// One line of the bill. Four of these on this screen and they have to line up.
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final int amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle? style = strong
        ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : t.bodyMedium?.copyWith(color: context.zc.textMuted);

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text('₹$amount', style: style),
        ],
      ),
    );
  }
}
