import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';
import 'package:zopiqnow/features/location/presentation/providers/location_providers.dart';
import 'package:zopiqnow/features/location/presentation/widgets/address_picker_sheet.dart';

/// The route the auth guard protects. Confirms *who* is ordering and *where* it
/// goes — the two things Step 5 exists to establish.
///
/// Payment is Step 6, and this screen says so rather than pretending. It is
/// deliberately not the checkout screen: no coupons, no payment methods, no
/// order placement.
class CheckoutPage extends ConsumerWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Cart cart = ref.watch(cartProvider);
    final CartBill bill = CartBill.of(cart);
    final Address? address = ref.watch(selectedAddressProvider);
    final AuthState auth = ref.watch(authControllerProvider);

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
            const SizedBox(height: ZopiqSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('To pay', style: t.titleMedium),
                Text('₹${bill.total}', style: t.titleLarge),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: 'Pay ₹${bill.total}',
              variant: ZopiqButtonVariant.cta,
              expand: true,
              // Razorpay lands in Step 6. A button that silently does nothing is
              // worse than one that is honestly unavailable.
              onPressed: null,
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Center(
              child: Text(
                'Payments arrive in the next step.',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
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
