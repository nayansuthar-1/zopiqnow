import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/notifications/domain/entities/rider_notification.dart';
import 'package:zopiq_rider/features/notifications/presentation/providers/notifications_providers.dart';

/// The rider's inbox: jobs that appeared, payouts sent, account changes — newest
/// first. A companion to push (once it ships), not a replacement. Reading one, or
/// all, is the only write the screen makes; the content is the database's.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RiderNotification>> async = ref.watch(
      notificationsProvider,
    );
    final int unread = ref.watch(unreadCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationsDataSourceProvider).markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: ZopiqLoader()),
          error: (Object _, StackTrace _) => const _Empty(
            icon: Icons.cloud_off_rounded,
            title: 'Notifications are out of reach',
            body: 'We couldn\'t load your inbox just now.',
          ),
          data: (List<RiderNotification> items) {
            if (items.isEmpty) {
              return const _Empty(
                icon: Icons.notifications_none_rounded,
                title: 'Nothing yet',
                body: 'New jobs, payouts and account updates show up here.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.pageGutter,
                vertical: ZopiqSpacing.lg,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: ZopiqSpacing.sm),
              itemBuilder: (BuildContext context, int i) =>
                  _NotificationCard(item: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.item});

  final RiderNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool unread = item.isUnread;
    final Color accent = switch (item.kind) {
      RiderNotificationKind.jobOffer => zc.primary,
      RiderNotificationKind.jobAvailable => zc.primary,
      RiderNotificationKind.jobCancelled => zc.nonVeg,
      RiderNotificationKind.message => zc.primary,
      RiderNotificationKind.payout => zc.veg,
      RiderNotificationKind.account => zc.nonVeg,
      RiderNotificationKind.warning => zc.nonVeg,
      RiderNotificationKind.system => zc.textMuted,
    };

    return ZopiqPressable(
      onTap: () {
        if (unread) ref.read(notificationsDataSourceProvider).markRead(item.id);
      },
      child: ZopiqCard(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(item.kind), color: accent, size: 20),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: t.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      color: zc.textStrong,
                    ),
                  ),
                  if (item.body != null) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      item.body!,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                  const SizedBox(height: ZopiqSpacing.xs),
                  Text(
                    _when(item.createdAt),
                    style: t.labelSmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            if (unread) ...<Widget>[
              const SizedBox(width: ZopiqSpacing.sm),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: zc.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(RiderNotificationKind kind) => switch (kind) {
    // An offer that reached the inbox is one the rider did not answer in time —
    // by the time it is read here it is history, so it reads as a missed call
    // rather than as something still on the table.
    RiderNotificationKind.jobOffer => Icons.notifications_active_rounded,
    RiderNotificationKind.jobAvailable => Icons.delivery_dining_rounded,
    RiderNotificationKind.jobCancelled => Icons.cancel_outlined,
    RiderNotificationKind.message => Icons.chat_bubble_rounded,
    RiderNotificationKind.payout => Icons.account_balance_wallet_rounded,
    RiderNotificationKind.account => Icons.manage_accounts_rounded,
    RiderNotificationKind.warning => Icons.warning_amber_rounded,
    RiderNotificationKind.system => Icons.info_outline_rounded,
  };

  /// `just now`, `12m ago`, `3h ago`, then a date once it's a day old.
  static String _when(DateTime when) {
    final Duration ago = DateTime.now().difference(when);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
    if (ago.inHours < 24) return '${ago.inHours}h ago';

    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${when.day} ${months[when.month - 1]}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

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
            Icon(icon, size: 48, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.md),
            Text(
              title,
              style: t.titleMedium?.copyWith(color: zc.textStrong),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
