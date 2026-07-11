import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_session.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/bill_summary.dart';
import 'package:zopiqnow/features/checkout/domain/entities/applied_coupon.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/domain/entities/placed_order.dart';
import 'package:zopiqnow/features/checkout/domain/gateways/payment_gateway.dart';
import 'package:zopiqnow/features/checkout/domain/repositories/order_repository.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/address_picker_sheet.dart';

/// Checkout: who is ordering, where it goes, what it costs after a coupon, and
/// how it's paid. Auth-guarded — only signed-in users reach it.
///
/// UPI settles through the mock gateway until the Razorpay keys and the
/// payment-order endpoint land (Step 7). The tile says so: a test payment that
/// looks like a real one is worse than one that admits what it is.
class CheckoutPage extends ConsumerWidget {
  const CheckoutPage({super.key});

  Future<void> _placeOrder(
    BuildContext context,
    WidgetRef ref,
    Address address,
    AuthUser user,
  ) async {
    try {
      final PlacedOrder? order = await ref
          .read(checkoutControllerProvider.notifier)
          .placeOrder(deliveryAddress: address, user: user);
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
    final AuthState auth = ref.watch(authControllerProvider);
    final CheckoutState checkout = ref.watch(checkoutControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          children: <Widget>[
            _SectionCard(
              icon: Icons.location_on_rounded,
              title: 'Deliver to',
              body: address?.shortDisplay ?? 'No address selected',
              actionLabel: address == null ? 'Select' : 'Change',
              onAction: () => showAddressPicker(context),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            if (auth is AuthSignedIn)
              _SectionCard(
                icon: Icons.person_rounded,
                title: 'Ordering as',
                body: '+91 ${auth.user.displayPhone}',
                actionLabel: 'Sign out',
                onAction: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            const SizedBox(height: ZopiqSpacing.md),
            _OrderSummaryCard(cart: cart),
            const SizedBox(height: ZopiqSpacing.md),
            const _CouponCard(),
            const SizedBox(height: ZopiqSpacing.md),
            BillSummary(bill: bill),
            const SizedBox(height: ZopiqSpacing.md),
            _PaymentMethods(
              selected: checkout.paymentMethod,
              onSelect: (PaymentMethod m) => ref
                  .read(checkoutControllerProvider.notifier)
                  .selectPaymentMethod(m),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ZopiqButton(
              // A tap with no address opens the picker — never a dead button.
              label: address == null
                  ? 'Select delivery address'
                  : checkout.paymentMethod == PaymentMethod.upi
                  ? 'Pay ₹${bill.total}'
                  : 'Place order · ₹${bill.total}',
              variant: ZopiqButtonVariant.cta,
              isLoading: checkout.isPlacingOrder,
              // The route is auth-guarded, so `auth` is AuthSignedIn here. The
              // pattern match is what proves it rather than a `!`.
              onPressed: address == null || auth is! AuthSignedIn
                  ? () => showAddressPicker(context)
                  : () => _placeOrder(context, ref, address, auth.user),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              checkout.paymentMethod == PaymentMethod.cod
                  ? 'Pay ₹${bill.total} in cash when your order arrives.'
                  : 'Test gateway — no money moves until the Razorpay keys are '
                        'live.',
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
    final List<String> hints =
        ref.watch(couponHintsProvider).valueOrNull ?? const <String>[];

    if (coupon != null) {
      return ZopiqCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.local_offer_rounded, color: zc.veg, size: 22),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${coupon.code} applied', style: t.titleSmall),
                  Text(
                    'You save ₹${coupon.discount} on this order',
                    style: t.bodySmall?.copyWith(color: zc.veg),
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
          const SizedBox(height: ZopiqSpacing.xs),
          // There is no marketing campaign behind these codes yet, so the screen
          // is the campaign. Goes away with the promotions service. Silent while
          // loading or on failure: a missing hint is not worth a spinner, and it
          // is certainly not worth an error.
          if (hints.isNotEmpty)
            Text(
              'Try ${hints.join('  ·  ')}',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
        ],
      ),
    );
  }
}

class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods({required this.selected, required this.onSelect});

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelect;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Pay with', style: t.titleMedium),
          const SizedBox(height: ZopiqSpacing.sm),
          _PaymentTile(
            method: PaymentMethod.cod,
            icon: Icons.payments_outlined,
            title: 'Cash on delivery',
            subtitle: 'Pay when your food arrives',
            selected: selected == PaymentMethod.cod,
            onSelect: onSelect,
          ),
          _PaymentTile(
            method: PaymentMethod.upi,
            icon: Icons.qr_code_rounded,
            title: 'UPI',
            subtitle: 'Test gateway · no real money',
            selected: selected == PaymentMethod.upi,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.method,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelect,
  });

  final PaymentMethod method;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  /// Null renders the tile disabled (method not available yet).
  final ValueChanged<PaymentMethod>? onSelect;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool enabled = onSelect != null;
    final Color textColor = enabled ? zc.textStrong : zc.textMuted;

    return InkWell(
      onTap: enabled ? () => onSelect!(method) : null,
      borderRadius: ZopiqRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22, color: enabled ? zc.primary : zc.textMuted),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: t.titleSmall?.copyWith(color: textColor)),
                  Text(
                    subtitle,
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 22,
              color: selected ? zc.primary : zc.textMuted,
            ),
          ],
        ),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Row(
        children: <Widget>[
          Icon(icon, color: zc.primary, size: 22),
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
                  style: t.titleSmall,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
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
