import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';

/// Gift orders, newest first.
///
/// A separate history from food and not a filter on it: the two are different
/// orders, fulfilled by different people, with different states. A single list
/// mixing "Out for delivery" (a rider, twenty minutes) with "On its way" (a
/// courier, some days) would be one word doing two jobs.
class GiftOrdersPage extends ConsumerWidget {
  const GiftOrdersPage({
    required this.onOpen,
    required this.onBrowse,
    super.key,
  });

  final void Function(String orderId) onOpen;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<GiftOrder>> orders = ref.watch(giftOrdersProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        // Same fallback as My orders: two of the ways here leave nothing to pop.
        leading: BackButton(
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : onBrowse(),
        ),
        title: const Text('Gift orders'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: orders.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object _, StackTrace _) => _Message(
          icon: Icons.cloud_off_rounded,
          title: 'We couldn\'t load your gift orders',
          body: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(giftOrdersProvider),
        ),
        data: (List<GiftOrder> list) {
          if (list.isEmpty) {
            return _Message(
              icon: Icons.card_giftcard_rounded,
              title: 'No gift orders yet',
              body: 'Gifts you buy will show up here.',
              actionLabel: 'Browse gifts',
              onAction: onBrowse,
            );
          }
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.refresh(giftOrdersProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
                vertical: ZopiqSpacing.md,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: ZopiqSpacing.md),
              itemBuilder: (BuildContext context, int i) =>
                  _GiftOrderCard(order: list[i], onTap: () => onOpen(list[i].id)),
            ),
          );
        },
      ),
    );
  }
}

class _GiftOrderCard extends StatelessWidget {
  const _GiftOrderCard({required this.order, required this.onTap});

  final GiftOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      elevated: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: ZopiqRadii.rMd,
        child: Padding(
          padding: const EdgeInsets.all(ZopiqSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      order.shopName,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GiftStatusPill(status: order.status),
                ],
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                '${order.id} · ${order.itemCount} item'
                '${order.itemCount == 1 ? '' : 's'} · ₹${order.total}',
                style: t.bodySmall?.copyWith(color: zc.textMuted),
              ),
              // The courier, on the card, for the one status where it exists.
              // Somebody checking on a parcel should not have to open anything.
              if (order.status == GiftOrderStatus.dispatched &&
                  order.courierName != null) ...<Widget>[
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  'With ${order.courierName}'
                  '${order.trackingRef == null ? '' : ' · ${order.trackingRef}'}',
                  style: t.bodySmall?.copyWith(
                    color: zc.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The status, as a pill. Shared with the detail screen so one order never
/// reads two different ways on two screens.
class GiftStatusPill extends StatelessWidget {
  const GiftStatusPill({required this.status, super.key});

  final GiftOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final Color color = switch (status) {
      GiftOrderStatus.delivered => zc.veg,
      GiftOrderStatus.cancelled => zc.nonVeg,
      _ => zc.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Text(
        status.label,
        style: t.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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
