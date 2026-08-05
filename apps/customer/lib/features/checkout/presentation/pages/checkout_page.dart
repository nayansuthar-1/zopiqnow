import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/auth/presentation/widgets/delivery_phone_sheet.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/bill_summary.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/restaurant_offer.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/domain/entities/delivery_area.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/delivery_notes_sheet.dart';
import 'package:zopiqnow/features/location/presentation/widgets/address_picker_sheet.dart';

/// Checkout: who is ordering, where it goes, what it costs after a coupon, and
/// how it's paid. Auth-guarded — only signed-in users reach it.
///
/// UPI settles through Razorpay, and through the mock only while the merchant
/// keys are unset — the server decides which, not this screen (launch C2). The
/// row says so whenever it is the mock: a test payment that looks like a real
/// one is worse than one that admits what it is.
class CheckoutPage extends ConsumerWidget {
  const CheckoutPage({super.key});

  Future<void> _placeOrder(
    BuildContext context,
    WidgetRef ref,
    Address address,
    String userPhone,
  ) async {
    try {
      final PlacedOrder? order = await ref
          .read(checkoutControllerProvider.notifier)
          .placeOrder(deliveryAddress: address, userPhone: userPhone);
      // Null: the customer closed the payment sheet. They know — no snackbar.
      if (order != null && context.mounted) {
        context.pushReplacementNamed(Routes.orderSuccess);
      }
    } on PaymentFailure catch (failure) {
      if (context.mounted) _showFailure(context, failure.message);
    } on OrderPlacementFailure catch (failure) {
      if (context.mounted) _showFailure(context, failure.message);
    }
  }

  void _showFailure(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Cart cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      // Just placed an order: the success page is replacing this route, so
      // render nothing rather than flashing "cart is empty" mid-transition.
      if (ref.watch(lastPlacedOrderProvider) != null) {
        return Scaffold(appBar: AppBar(title: const Text('Checkout')));
      }
      return const _EmptyCheckout();
    }

    final CartBill bill = ref.watch(checkoutBillProvider);
    final Address? address = ref.watch(selectedAddressProvider);
    final String? notes = ref.watch(deliveryNotesProvider);
    final AuthState auth = ref.watch(authControllerProvider);
    final CheckoutState checkout = ref.watch(checkoutControllerProvider);

    // Null until the user gives one. `place_order` will not take an order
    // without a number to call, so neither will the button below.
    final String? phone = auth is AuthSignedIn ? auth.user.phone : null;

    // Everything the order still needs, in the order the screen asks for it. The
    // CTA below is driven by the *first* gap, so the button always offers the
    // next thing to do rather than refusing to do anything.
    final bool needsAddress = address == null;
    final bool needsPhone = phone == null;

    // Do we deliver there? (Migration 0098.) Asked here and not in `place_order`
    // because the gateway runs *first* — an order the trigger refuses is an
    // order somebody has already paid for.
    //
    // Only `false` blocks. While the answer is in flight, and if it never
    // arrives, the button stays live: the check fails open by design (see
    // `AddressRepositoryImpl.deliveryArea`), and a customer standing in Sadri on
    // a bad connection must not be told we do not deliver to them.
    final DeliveryAreaVerdict? area = address == null
        ? null
        : ref
              .watch(
                deliveryAreaProvider((
                  lat: address.latitude,
                  lng: address.longitude,
                )),
              )
              .valueOrNull;
    // The refusal itself rather than a bool, so every use below carries the
    // wording with it and the compiler promotes it without a `!`.
    final DeliveryAreaVerdict? refusal = area != null && !area.serviceable
        ? area
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          children: <Widget>[
            // Above everything, because it decides whether any of the rest is
            // worth reading. Its own card rather than a snackbar: a customer who
            // has just been told we do not reach them will want to read the
            // sentence twice, and a snackbar is gone in four seconds.
            if (refusal != null) ...<Widget>[
              ZopiqReveal(child: _OutOfAreaCard(verdict: refusal)),
              const SizedBox(height: ZopiqSpacing.md),
            ],
            ZopiqReveal(
              child: ZopiqCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _SectionCard(
                      icon: Icons.location_on_rounded,
                      title: 'Deliver to',
                      body: address?.shortDisplay ?? 'No address selected',
                      actionLabel: needsAddress ? 'Select' : 'Change',
                      isMissing: needsAddress,
                      onAction: () => showAddressPicker(context),
                    ),
                    if (auth is AuthSignedIn) ...[
                      Divider(height: 1, color: zc.divider),
                      _SectionCard(
                        icon: Icons.person_rounded,
                        title: 'Ordering as',
                        body: auth.user.email,
                        actionLabel: 'Sign out',
                        onAction: () =>
                            ref.read(authControllerProvider.notifier).signOut(),
                      ),
                      Divider(height: 1, color: zc.divider),
                      _SectionCard(
                        icon: Icons.call_rounded,
                        title: 'Rider calls',
                        body: auth.user.phone ?? 'No number yet',
                        actionLabel: needsPhone ? 'Add' : 'Change',
                        isMissing: needsPhone,
                        onAction: () => showDeliveryPhoneSheet(context),
                      ),
                      Divider(height: 1, color: zc.divider),
                      // Optional, and never [isMissing]: an order with no note
                      // is a perfectly good order, and a warm border round a
                      // blank field would be checkout inventing an obstacle.
                      _SectionCard(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Note for the rider',
                        body: notes ?? 'Gate number, landmark, floor…',
                        actionLabel: notes == null ? 'Add' : 'Change',
                        onAction: () => showDeliveryNotesSheet(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            ZopiqReveal(index: 1, child: _OrderSummaryCard(cart: cart)),
            const SizedBox(height: ZopiqSpacing.md),
            const ZopiqReveal(index: 2, child: _CouponCard()),
            const SizedBox(height: ZopiqSpacing.md),
            ZopiqReveal(index: 3, child: BillSummary(bill: bill)),
            const SizedBox(height: ZopiqSpacing.md),
            const ZopiqReveal(index: 4, child: _PaymentMethods()),
          ],
        ),
      ),
      bottomNavigationBar: _PlaceOrderBar(
        bill: bill,
        // A tap with something missing opens the thing that fills it in — never
        // a dead button.
        label: needsAddress
            ? 'Select delivery address'
            : refusal != null
            ? 'Choose an address we deliver to'
            : needsPhone
            ? 'Add a delivery number'
            : 'Pay ₹${bill.total}',
        caption: refusal != null
            ? refusal.headline
            : 'Test gateway — no money moves until the Razorpay keys are live.',
        isLoading: checkout.isPlacingOrder,
        // The route is auth-guarded, so `auth` is AuthSignedIn here. The pattern
        // match is what proves it rather than a `!`.
        //
        // Out of area sends them back to the picker rather than going dead —
        // the same rule the rest of this bar follows: a tap with something
        // missing opens the thing that fills it in.
        onPressed: needsAddress || refusal != null || auth is! AuthSignedIn
            ? () => showAddressPicker(context)
            : needsPhone
            ? () => showDeliveryPhoneSheet(context)
            : () => _placeOrder(context, ref, address, phone),
      ),
    );
  }
}

/// The sticky foot of checkout: what it costs, the one button, and the sentence
/// that says what the button will actually do.
class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({
    required this.bill,
    required this.label,
    required this.caption,
    required this.isLoading,
    required this.onPressed,
  });

  final CartBill bill;
  final String label;
  final String caption;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: zc.divider)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: zc.primary.withValues(alpha: 0.04),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ZopiqButton(
              label: label,
              variant: ZopiqButtonVariant.cta,
              isLoading: isLoading,
              onPressed: onPressed,
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              caption,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact recap of what's being ordered; editing happens back in the cart.
class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            cart.restaurantName ?? 'Your order',
            style: t.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          for (final CartLine line in cart.lines)
            Padding(
              padding: const EdgeInsets.only(top: ZopiqSpacing.xs),
              child: Row(
                children: <Widget>[
                  ZopiqVegIndicator(isVeg: line.item.isVeg),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Text(
                      '${line.quantity} × ${line.item.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium,
                    ),
                  ),
                  Text(
                    '₹${line.lineTotal}',
                    style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Coupon entry / applied-coupon display. Local state is just the text field;
/// apply results live in [checkoutControllerProvider].
class _CouponCard extends ConsumerStatefulWidget {
  const _CouponCard();

  @override
  ConsumerState<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends ConsumerState<_CouponCard> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final CheckoutState checkout = ref.watch(checkoutControllerProvider);
    final AppliedCoupon? coupon = checkout.coupon;
    final List<RestaurantOffer> offers =
        ref.watch(offersProvider).valueOrNull ?? const <RestaurantOffer>[];

    if (coupon != null) {
      // An applied coupon is a small win, and it should feel like one: green,
      // bordered, and visibly a *ticket* rather than one more grey row on a
      // screen the customer is trying to get off.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.xs, vertical: ZopiqSpacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: zc.veg.withValues(alpha: 0.08),
            borderRadius: ZopiqRadii.rLg,
          ),
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.lg),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.confirmation_num_rounded,
                  color: zc.textMuted,
                  size: 22,
                ),
              const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${coupon.code} applied',
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'You save ₹${coupon.discount} on this order',
                      style: t.bodySmall?.copyWith(
                        color: zc.veg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove coupon',
                onPressed: () =>
                    ref.read(checkoutControllerProvider.notifier).removeCoupon(),
              ),
            ],
          ),
        ),
      ),
    );
  }

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (String code) => ref
                      .read(checkoutControllerProvider.notifier)
                      .applyCoupon(code),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter coupon code',
                    errorText: checkout.couponError,
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                  ),
                ),
              ),
              const SizedBox(width: ZopiqSpacing.sm),
              TextButton(
                onPressed: checkout.isApplyingCoupon
                    ? null
                    : () => ref
                          .read(checkoutControllerProvider.notifier)
                          .applyCoupon(_code.text),
                child: Text(checkout.isApplyingCoupon ? 'APPLYING…' : 'APPLY'),
              ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          // The offers this cart can actually use — Zopiqnow's, and this
          // kitchen's (0064). Tappable, because a code the customer can see is a
          // code they should not have to retype. Silent while loading or on
          // failure: a missing offer is not worth a spinner, and it is certainly
          // not worth an error.
          for (final RestaurantOffer offer in offers)
            _OfferChip(
              offer: offer,
              onTap: checkout.isApplyingCoupon
                  ? null
                  : () {
                      _code.text = offer.code;
                      ref
                          .read(checkoutControllerProvider.notifier)
                          .applyCoupon(offer.code);
                    },
            ),
        ],
      ),
    );
  }
}

/// One advertised offer, as a row you can tap to apply.
///
/// A kitchen's own offer is marked as one. That is the whole point of 0064 from
/// the customer's side: "only at Paradise Biryani" is why this code is better
/// than the platform ones above it, and a list where every row looks identical
/// hides the one thing worth knowing.
class _OfferChip extends StatelessWidget {
  const _OfferChip({required this.offer, this.onTap});

  final RestaurantOffer offer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ZopiqRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
        child: Row(
          children: <Widget>[
            Icon(Icons.local_offer_rounded, size: 16, color: zc.veg),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        offer.code,
                        style: t.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (offer.isExclusive) ...<Widget>[
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          '· only here',
                          style: t.labelSmall?.copyWith(
                            color: zc.veg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    offer.minSubtotal > 0
                        ? '${offer.label} on orders over ₹${offer.minSubtotal}'
                        : offer.label,
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              'APPLY',
              style: t.labelMedium?.copyWith(
                color: zc.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the order is paid. There is one answer and it is not a choice: UPI, up
/// front, through the gateway (launch C1). Cash on delivery was removed rather
/// than disabled — a greyed-out row is an invitation to ask when it is coming
/// back, and the answer is that it is not.
///
/// The card stays even though it decides nothing. What the customer is about to
/// be charged through, and that it is a test gateway, are both things checkout
/// owes them before the button rather than after it.
class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Pay with', style: t.titleMedium),
          const SizedBox(height: ZopiqSpacing.sm),
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.md),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.06),
              borderRadius: ZopiqRadii.rMd,
              border: Border.all(color: zc.primary, width: 1.5),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.qr_code_rounded, size: 22, color: zc.textStrong),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'UPI',
                        style: t.titleSmall?.copyWith(
                          color: zc.textStrong,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Test gateway · no real money',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle_rounded, size: 22, color: zc.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "We'll be there soon" — the delivery area, stated once and plainly.
///
/// Both sentences come from `delivery_area_check` (0098) rather than from here,
/// so the towns named in the copy are the towns in `service_areas` and adding a
/// third is an INSERT rather than a release.
///
/// Warm, not alarming: this is not an error the customer made. The restrained
/// treatment is deliberate — a red banner for "we don't reach your street yet"
/// reads as a fault, and the honest tone is closer to an apology than a warning.
class _OutOfAreaCard extends StatelessWidget {
  const _OutOfAreaCard({required this.verdict});

  final DeliveryAreaVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.sm),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rSm,
            ),
            child: Icon(
              Icons.pin_drop_outlined,
              color: zc.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  verdict.headline,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  verdict.detail,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.isMissing = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  /// This row is *why* the order cannot be placed — no address, no phone. It
  /// gets a warm border and a filled action, so the customer's eye lands on the
  /// thing standing in their way instead of hunting for it after the button
  /// refuses to do what they expected.
  final bool isMissing;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final Widget card = InkWell(
      onTap: onAction,
      borderRadius: ZopiqRadii.rLg,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ZopiqSpacing.sm,
          horizontal: ZopiqSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: zc.textMuted, size: 22),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title, style: t.labelSmall?.copyWith(color: zc.textMuted)),
                  Text(
                    body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      color: isMissing ? zc.textMuted : zc.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );

    if (!isMissing) return card;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: zc.primary.withValues(alpha: 0.45), width: 1.5),
      ),
      child: card,
    );
  }
}

/// Reachable by deep-linking `/checkout` with nothing in the cart.
class _EmptyCheckout extends StatelessWidget {
  const _EmptyCheckout();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.shopping_bag_outlined, size: 56, color: zc.textMuted),
              const SizedBox(height: ZopiqSpacing.lg),
              Text('Nothing to check out', style: t.titleMedium),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Add something to your cart first.',
                style: t.bodyMedium?.copyWith(color: zc.textMuted),
                textAlign: TextAlign.center,
              ),
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
}
