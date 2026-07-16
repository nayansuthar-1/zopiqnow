import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart';

/// "Your orders" — the customer's own receipts, newest first.
///
/// Auth-guarded by the router (`/orders` is a protected prefix), so this screen
/// never has to render a signed-out state: there is no such thing as someone
/// else's order history, and the guard is what says so.
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  /// The order whose reorder is in flight, so only *that* card spins. A single
  /// bool would light up every button on the screen.
  String? _reorderingId;

  Future<void> _reorder(CustomerOrder order) async {
    final Cart cart = ref.read(cartProvider);

    // Same rule, same words as the menu screen: a cart belongs to one
    // restaurant, and emptying someone's cart without asking is not a feature.
    if (cart.isNotEmpty && cart.restaurantId != order.restaurantId) {
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Start a new cart?'),
          content: Text(
            'Your cart has items from ${cart.restaurantName}. Reordering from '
            '${order.restaurantName} will empty it.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep my cart'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start new cart'),
            ),
          ],
        ),
      );
      if (!(replace ?? false)) return;
    }

    setState(() => _reorderingId = order.id);
    try {
      final ReorderOutcome outcome = await ref
          .read(reorderControllerProvider.notifier)
          .reorder(order);
      if (!mounted) return;

      if (outcome.isEmpty) {
        _say('Nothing from this order is available right now.');
        return;
      }
      if (outcome.unavailable > 0) {
        _say(
          '${outcome.unavailable} item${outcome.unavailable == 1 ? '' : 's'} '
          'from this order ${outcome.unavailable == 1 ? 'is' : 'are'} no longer '
          'available. The rest is in your cart.',
        );
      }
      context.goNamed(Routes.cart);
    } on Object {
      // The menu fetch failed — the cart is untouched (the controller only
      // writes it on success), so there is nothing to undo and nothing to
      // explain beyond "it didn't work".
      if (mounted) _say('We couldn\'t load that menu. Please try again.');
    } finally {
      if (mounted) setState(() => _reorderingId = null);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CustomerOrder>> orders = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My orders'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: orders.when(
        loading: () => const _OrdersSkeleton(),
        error: (Object _, StackTrace _) => _OrdersMessage(
          icon: Icons.cloud_off_rounded,
          title: 'We couldn\'t load your orders',
          body: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(ordersProvider),
        ),
        data: (List<CustomerOrder> data) {
          if (data.isEmpty) {
            return _OrdersMessage(
              icon: Icons.receipt_long_rounded,
              title: 'No orders yet',
              body: 'Your past orders will show up here.',
              actionLabel: 'Browse restaurants',
              onAction: () => context.goNamed(Routes.home),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(ordersProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              itemCount: data.length,
              itemBuilder: (BuildContext context, int i) {
                final CustomerOrder order = data[i];
                // One tile's spinner must not repaint the rest of the list.
                return RepaintBoundary(
                  child: OrderCard(
                    order: order,
                    isReordering: _reorderingId == order.id,
                    onReorder: () => _reorder(order),
                    onTap: () => context.pushNamed(
                      Routes.orderDetail,
                      pathParameters: <String, String>{'id': order.id},
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Shimmer in the shape of the cards it precedes, so the screen does not jump
/// when the real thing lands.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      itemCount: 4,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.xs,
        ),
        child: ZopiqShimmer(
          child: SizedBox(
            height: 148,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.zc.shimmerBase,
                borderRadius: ZopiqRadii.rLg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty and error states, which differ only in their words.
class _OrdersMessage extends StatelessWidget {
  const _OrdersMessage({
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(title, style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: actionLabel,
              expand: false,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}
