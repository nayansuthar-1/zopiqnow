import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/store_status_banner.dart';
import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/order_ticket.dart';

/// The kitchen's screen — live orders worklist for merchant cooks.
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
            VendorFadeSlide(
              child: _Header(vendor: vendor, queueCount: queue.length, newCount: newCount),
            ),
            
            // ── 2. Animated Status Banner ──
            if (vendor != null)
              VendorFadeSlide(
                delay: const Duration(milliseconds: 50),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.pageGutter,
                    vertical: ZopiqSpacing.xs,
                  ),
                  child: StoreStatusBanner(vendor: vendor),
                ),
              ),

            // ── 3. Queue List ──
            Expanded(
              child: orders.when(
                loading: () => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CircularProgressIndicator(color: context.zc.primary),
                      const SizedBox(height: ZopiqSpacing.md),
                      Text(
                        'Connecting to live kitchen terminal...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.zc.textMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                error: (Object _, StackTrace _) => _Message(
                  iconType: VendorSvgType.storeClosed,
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
                      iconType: VendorSvgType.liveOrders,
                      title: 'All caught up',
                      body: 'New orders appear here the moment they\'re placed.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
                    itemCount: queue.length,
                    itemBuilder: (BuildContext context, int i) {
                      return VendorFadeSlide(
                        delay: Duration(milliseconds: i * 60),
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
        ZopiqSpacing.xs,
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
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.sm),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rMd,
            ),
            child: VendorSvgIcon(
              type: VendorSvgType.chefMenu,
              size: 24,
              color: zc.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.iconType,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final VendorSvgType iconType;
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
            VendorSvgIcon(
              type: iconType,
              size: 56,
              color: zc.textMuted,
            ),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
