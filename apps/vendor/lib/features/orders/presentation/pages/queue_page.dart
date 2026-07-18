import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/store_status_banner.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_ticket.dart';

/// The kitchen's screen — the app's home, and the tab a cook lives on.
///
/// A restaurant tablet is glanced at, across a room, by someone holding a pan.
/// So the queue is nothing but the list: every order that still needs a human,
/// oldest first, with its next action on it, and the open/closed switch above.
/// The slower rooms — history, the menu, the profile — are a tab away, not on
/// this screen, because a cook mid-rush should not have to scroll past them.
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);
    final AsyncValue<List<VendorOrder>> orders = ref.watch(ordersProvider);
    final List<VendorOrder> queue = ref.watch(queueProvider);
    final int newCount = ref.watch(newOrderCountProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── 1. Custom Header ──
            ZopiqReveal(
              index: 0,
              child: _Header(vendor: vendor, queueCount: queue.length, newCount: newCount),
            ),
            
            // ── 2. Animated Status Banner ──
            if (vendor != null)
              ZopiqReveal(
                index: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.pageGutter,
                    vertical: ZopiqSpacing.sm,
                  ),
                  child: StoreStatusBanner(vendor: vendor),
                ),
              ),

            // ── 3. Queue List ──
            Expanded(
              child: orders.when(
                loading: () => const Center(child: CircularProgressIndicator()),
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
                      return ZopiqReveal(
                        index: 2 + i, // Staggered reveal for tickets
                        child: RepaintBoundary(
                          child: OrderTicket(
                            key: ValueKey<String>(queue[i].id),
                            order: queue[i],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.vendor,
    required this.queueCount,
    required this.newCount,
  });

  final Vendor? vendor;
  final int queueCount;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Active Orders',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  newCount == 0
                      ? '$queueCount in the queue'
                      : '$newCount new · $queueCount in the queue',
                  style: t.bodyMedium?.copyWith(
                    color: newCount > 0 ? zc.primary : zc.textMuted,
                    fontWeight: newCount > 0 ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
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
