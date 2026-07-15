import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_ticket.dart';

/// The kitchen's screen. There is only one, and that is the design.
///
/// A restaurant tablet is not browsed — it is glanced at, across a room, by
/// someone holding a pan. So there are no tabs, no navigation, and nothing to
/// find: every order that still needs a human is on this list, oldest first,
/// with its next action on it. The moment an order is delivered it leaves.
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);
    final AsyncValue<List<VendorOrder>> orders = ref.watch(ordersProvider);
    final List<VendorOrder> queue = ref.watch(queueProvider);
    final int newCount = ref.watch(newOrderCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(vendor?.restaurantName ?? 'Zopiqnow Partner'),
            Text(
              newCount == 0
                  ? '${queue.length} in the queue'
                  : '$newCount new · ${queue.length} in the queue',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.zc.textMuted),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.restaurant_menu_rounded),
            onPressed: () => context.goNamed(Routes.menu),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(vendorAuthControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // The socket dropped, or the first read failed. The kitchen is blind
        // either way and has to be told so — a stale, empty list would read as
        // "no orders", which is the most expensive lie this app could tell.
        error: (Object _, StackTrace _) => _Message(
          icon: Icons.cloud_off_rounded,
          title: 'We\'ve lost the connection',
          body:
              'Orders can\'t reach you until this is back. '
              'Check the internet and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(ordersProvider),
        ),
        data: (_) {
          if (queue.isEmpty) {
            return const _Message(
              icon: Icons.done_all_rounded,
              title: 'All caught up',
              body: 'New orders appear here the moment they\'re placed.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
            itemCount: queue.length,
            itemBuilder: (BuildContext context, int i) {
              // One ticket's button spinning must not repaint the queue.
              return RepaintBoundary(
                child: OrderTicket(
                  key: ValueKey<String>(queue[i].id),
                  order: queue[i],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The empty and disconnected states, which differ in their words and in whether
/// there is anything to do about them.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

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
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: actionLabel!,
                expand: false,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
