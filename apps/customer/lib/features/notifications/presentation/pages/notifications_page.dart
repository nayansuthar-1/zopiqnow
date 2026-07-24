import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/notifications/domain/entities/customer_notification.dart';
import 'package:zopiqnow/features/notifications/presentation/providers/notifications_providers.dart';

/// The customer's inbox: what happened to their orders, newest first.
///
/// A companion to push (once it ships), not a replacement — push rings a device
/// that is away, this is the record it comes back to. Reading one, or all, is the
/// only write the screen makes; the content is the database's.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CustomerNotification>> async = ref.watch(
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object _, StackTrace _) => _Empty(
            icon: Icons.cloud_off_rounded,
            title: 'Notifications are out of reach',
            body: 'We couldn\'t load your inbox just now.',
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (List<CustomerNotification> items) {
            if (items.isEmpty) {
              return const _Empty(
                icon: Icons.notifications_none_rounded,
                title: 'Nothing yet',
                body: 'Updates about your orders will show up here.',
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
              itemBuilder: (BuildContext context, int i) => ZopiqReveal(
                index: i,
                child: _NotificationCard(item: items[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.item});

  final CustomerNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool unread = item.isUnread;
    final Color accent = switch (item.kind) {
      CustomerNotificationKind.orderUpdate => zc.primary,
      CustomerNotificationKind.system => zc.textMuted,
    };

    return ZopiqPressable(
      onTap: () {
        if (unread) ref.read(notificationsDataSourceProvider).markRead(item.id);
        // The deep link: an order update opens that order's detail.
        if (item.orderId != null) {
          context.pushNamed(
            Routes.orderDetail,
            pathParameters: <String, String>{'id': item.orderId!},
          );
        }
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

  static IconData _iconFor(CustomerNotificationKind kind) => switch (kind) {
    CustomerNotificationKind.orderUpdate => Icons.receipt_long_rounded,
    CustomerNotificationKind.system => Icons.info_outline_rounded,
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

/// A centred icon + message, used for both the empty and the error states.
class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

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
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.lg),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
