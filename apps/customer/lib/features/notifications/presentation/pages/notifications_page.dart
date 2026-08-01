import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/notifications/domain/entities/customer_notification.dart';
import 'package:zopiqnow/features/notifications/presentation/providers/notifications_providers.dart';

/// The customer's inbox: exact Zomato-grade flat notification feed layout.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CustomerNotification>> async = ref.watch(
      notificationsProvider,
    );
    final int unread = ref.watch(unreadCountProvider);
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top Navigation & Action Row (Zomato style)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      size: 24,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  GestureDetector(
                    onTap: unread > 0
                        ? () => ref
                            .read(notificationsDataSourceProvider)
                            .markAllRead()
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        'Mark all as read',
                        style: t.labelLarge?.copyWith(
                          color: unread > 0
                              ? (isDark ? Colors.white70 : const Color(0xFF666666))
                              : (isDark ? Colors.white24 : const Color(0xFFCCCCCC)),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Large Section Title (Zomato Header)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Notifications',
                style: t.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF111111),
                ),
              ),
            ),

            // Content List / Empty / Error
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object _, StackTrace _) => _Empty(
                  icon: Icons.cloud_off_rounded,
                  title: 'Notifications are out of reach',
                  body: 'We couldn\'t load your inbox just now.',
                  onRetry: () => ref.invalidate(notificationsProvider),
                ),
                data: (List<CustomerNotification> items) {
                  if (items.isEmpty) {
                    return const _Empty(
                      icon: Icons.notifications_off_outlined,
                      title: 'Nothing yet',
                      body: 'Updates about your orders will show up here.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int i) => ZopiqReveal(
                      index: i,
                      child: _NotificationTile(
                        item: items[i],
                        isLast: i == items.length - 1,
                      ),
                    ),
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

class _NotificationIconInfo {
  const _NotificationIconInfo(this.icon, this.bgColor);
  final IconData icon;
  final Color bgColor;
}

/// Zomato-grade flat notification list item (No cards, flat divider)
class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item, required this.isLast});

  final CustomerNotification item;
  final bool isLast;

  static _NotificationIconInfo _getIconInfo(
    CustomerNotification item,
    ZopiqColors zc,
    bool isDark,
  ) {
    final String text = '${item.title} ${item.body ?? ''}'.toLowerCase();

    // 1. Delivery & Rider tracking
    if (text.contains('delivered') ||
        text.contains('valet') ||
        text.contains('driver') ||
        text.contains('rider') ||
        text.contains('on the way') ||
        text.contains('reaching') ||
        text.contains('almost here') ||
        text.contains('doorstep') ||
        text.contains('speed') ||
        text.contains('minute')) {
      return const _NotificationIconInfo(
        Icons.sports_motorsports_rounded,
        Color(0xFF0C831F), // Emerald Delivery Green
      );
    }

    // 2. Order Accepted / Preparing / Kitchen
    if (text.contains('accept') ||
        text.contains('prepar') ||
        text.contains('cook') ||
        text.contains('kitchen') ||
        text.contains('chef') ||
        text.contains('receive') ||
        text.contains('confirm') ||
        text.contains('place')) {
      return _NotificationIconInfo(
        Icons.restaurant_rounded,
        zc.primary, // Zopiq Primary Brand
      );
    }

    // 3. Offers, Discounts, Gifts & Promotions
    if (text.contains('offer') ||
        text.contains('discount') ||
        text.contains('coupon') ||
        text.contains('cashback') ||
        text.contains('save') ||
        text.contains('deal') ||
        text.contains('free') ||
        text.contains('gift') ||
        text.contains('flat')) {
      return const _NotificationIconInfo(
        Icons.local_offer_rounded,
        Color(0xFF8B5CF6), // Purple
      );
    }

    // 4. Payment, Refund, Wallet & Receipts
    if (text.contains('refund') ||
        text.contains('payment') ||
        text.contains('paid') ||
        text.contains('wallet') ||
        text.contains('bill') ||
        text.contains('upi')) {
      return const _NotificationIconInfo(
        Icons.account_balance_wallet_rounded,
        Color(0xFF0284C7), // Blue
      );
    }

    // 5. Fallback based on Kind
    if (item.kind == CustomerNotificationKind.message) {
      return _NotificationIconInfo(
        Icons.chat_bubble_rounded,
        zc.primary,
      );
    }

    if (item.kind == CustomerNotificationKind.orderUpdate) {
      return _NotificationIconInfo(
        Icons.receipt_long_rounded,
        zc.primary,
      );
    }

    return _NotificationIconInfo(
      Icons.notifications_active_rounded,
      isDark ? const Color(0xFF33333E) : const Color(0xFF2E2E38),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool unread = item.isUnread;

    final _NotificationIconInfo info = _getIconInfo(item, zc, isDark);

    return InkWell(
      onTap: () {
        if (unread) {
          ref.read(notificationsDataSourceProvider).markRead(item.id);
        }
        if (item.orderId != null) {
          context.pushNamed(
            Routes.orderDetail,
            pathParameters: <String, String>{'id': item.orderId!},
          );
        }
      },
      child: Container(
        color: unread
            ? zc.primary.withValues(alpha: isDark ? 0.08 : 0.03)
            : Colors.transparent,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Contextual Icon Avatar Circle
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: info.bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        info.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Notification Text Body
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Title
                        Text(
                          item.title,
                          style: t.titleSmall?.copyWith(
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w700,
                            fontSize: 15,
                            height: 1.25,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E1E1E),
                          ),
                        ),
                        if (item.body != null && item.body!.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            item.body!,
                            style: t.bodyMedium?.copyWith(
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF4A4A4A),
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _when(item.createdAt),
                          style: t.labelSmall?.copyWith(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF9E9E9E),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Unread Dot Indicator
                  if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6, left: 8),
                      decoration: BoxDecoration(
                        color: zc.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),

            // Flat Zomato-style horizontal divider
            if (!isLast)
              Padding(
                padding: const EdgeInsets.only(left: 84, right: 20),
                child: Divider(
                  height: 1,
                  thickness: 0.8,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFEEEEEE),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime when) {
    final Duration ago = DateTime.now().difference(when);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
    if (ago.inHours < 24) return '${ago.inHours}h ago';

    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${when.day} ${months[when.month - 1]}';
  }
}

/// Vertically centered empty/error state
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Align(
              alignment: const Alignment(0, -0.2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: zc.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 38,
                        color: zc.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      body,
                      style: t.bodyMedium?.copyWith(
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF64748B),
                        fontSize: 14,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (onRetry != null) ...<Widget>[
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: zc.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Retry',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


