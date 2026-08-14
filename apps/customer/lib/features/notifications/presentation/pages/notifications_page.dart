import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/notifications/domain/entities/customer_notification.dart';
import 'package:zopiqnow/features/notifications/presentation/providers/notifications_providers.dart';

/// The customer's inbox.
///
/// **Selection is a mode, not a control on every row.** A checkbox beside a
/// hundred notifications is a hundred controls nobody wants on the day they are
/// just reading one; tapping Select turns them on, and Cancel turns them off.
/// That is the shape Gmail and every photo gallery use, and it keeps the
/// ordinary path — open the inbox, tap the order — a single tap.
///
/// Deleting is deliberately **not** swipe-to-dismiss. A swipe deletes one row on
/// contact, and the thing being deleted here is the only record a customer has
/// that they were told something. Selecting, seeing a count, and confirming is
/// three deliberate acts to lose correspondence.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _selecting = false;

  /// Ids, not indices: the list is a live stream, so a row can arrive or leave
  /// while a selection is open and an index would silently come to mean a
  /// different notification.
  final Set<int> _selected = <int>{};

  bool _busy = false;

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _busy) return;
    final int count = _selected.length;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(count == 1 ? 'Delete this one?' : 'Delete $count?'),
        content: const Text('They will not come back.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final int deleted = await ref
          .read(notificationsDataSourceProvider)
          .deleteMany(_selected.toList(growable: false));
      if (!mounted) return;
      _exitSelection();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Text(
              deleted == 1 ? 'Notification deleted' : '$deleted deleted',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: const Text("We couldn't delete those. Try again."),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CustomerNotification>> async = ref.watch(
      notificationsProvider,
    );
    final int unread = ref.watch(unreadCountProvider);
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ZopiqColors zc = context.zc;
    final Color ink = isDark ? Colors.white : const Color(0xFF1E1E1E);

    final List<CustomerNotification> items =
        async.valueOrNull ?? const <CustomerNotification>[];
    final bool allSelected =
        items.isNotEmpty && _selected.length == items.length;

    return PopScope(
      // Back leaves the selection before it leaves the screen — the same rule
      // the shell applies to tabs, and the reason is the same: Back should undo
      // the last thing the customer did, not the whole visit.
      canPop: !_selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _selecting
                            ? ZopiqIcons.close
                            : ZopiqIcons.arrowLeft,
                        color: ink,
                        size: 22,
                      ),
                      onPressed: _selecting ? _exitSelection : context.pop,
                    ),
                    const Spacer(),
                    if (_selecting) ...<Widget>[
                      TextButton(
                        onPressed: items.isEmpty
                            ? null
                            : () => setState(() {
                                if (allSelected) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(
                                      items.map(
                                        (CustomerNotification n) => n.id,
                                      ),
                                    );
                                }
                              }),
                        child: Text(allSelected ? 'Clear all' : 'Select all'),
                      ),
                      IconButton(
                        tooltip: 'Delete selected',
                        icon: Icon(
                          ZopiqIcons.trash,
                          size: 22,
                          color: _selected.isEmpty ? zc.textMuted : zc.nonVeg,
                        ),
                        onPressed: _selected.isEmpty || _busy
                            ? null
                            : _deleteSelected,
                      ),
                    ] else ...<Widget>[
                      if (unread > 0)
                        TextButton(
                          onPressed: () => ref
                              .read(notificationsDataSourceProvider)
                              .markAllRead(),
                          child: const Text('Mark all as read'),
                        ),
                      IconButton(
                        tooltip: 'Select',
                        icon: Icon(
                          ZopiqIcons.checkSquare,
                          size: 22,
                          color: items.isEmpty ? zc.textMuted : ink,
                        ),
                        onPressed: items.isEmpty
                            ? null
                            : () => setState(() => _selecting = true),
                      ),
                    ],
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  _selecting
                      ? (_selected.isEmpty
                            ? 'Select notifications'
                            : '${_selected.length} selected')
                      : 'Notifications',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF111111),
                  ),
                ),
              ),

              Expanded(
                child: async.when(
                  loading: () => const Center(child: ZopiqLoader()),
                  error: (Object _, StackTrace _) => _Empty(
                    icon: ZopiqIcons.cloudSlash,
                    title: 'Notifications are out of reach',
                    body: 'We couldn\'t load your inbox just now.',
                    onRetry: () => ref.invalidate(notificationsProvider),
                  ),
                  data: (List<CustomerNotification> list) {
                    if (list.isEmpty) {
                      return const _Empty(
                        icon: ZopiqIcons.bellSlash,
                        title: 'Nothing yet',
                        body: 'Updates about your orders will show up here.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      itemBuilder: (BuildContext context, int i) {
                        final CustomerNotification n = list[i];
                        final bool picked = _selected.contains(n.id);

                        final Widget tile = _NotificationTile(
                          item: n,
                          isLast: i == list.length - 1,
                          // Suppressed while selecting: a tap has to mean
                          // "pick this", not "open the order and lose the
                          // selection behind a route change".
                          tapsEnabled: !_selecting,
                        );

                        if (!_selecting) {
                          return ZopiqReveal(index: i, child: tile);
                        }

                        return InkWell(
                          onTap: () => setState(() {
                            if (!_selected.add(n.id)) _selected.remove(n.id);
                          }),
                          child: Row(
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Icon(
                                  picked
                                      ? ZopiqIconsFill.checkCircle
                                      : ZopiqIcons.circle,
                                  size: 22,
                                  color: picked ? zc.primary : zc.textMuted,
                                ),
                              ),
                              Expanded(child: IgnorePointer(child: tile)),
                            ],
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
  const _NotificationTile({
    required this.item,
    required this.isLast,
    this.tapsEnabled = true,
  });

  final CustomerNotification item;
  final bool isLast;

  /// False while the page is in selection mode, where a tap has to mean "pick
  /// this row" rather than "open the order and lose the selection behind a
  /// route change".
  final bool tapsEnabled;

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
        ZopiqIconsFill.moped,
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
        ZopiqIconsFill.cookingPot,
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
        ZopiqIconsFill.tag,
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
        ZopiqIconsFill.wallet,
        Color(0xFF0284C7), // Blue
      );
    }

    // 5. Fallback based on Kind
    if (item.kind == CustomerNotificationKind.message) {
      return _NotificationIconInfo(
        ZopiqIconsFill.chat,
        zc.primary,
      );
    }

    if (item.kind == CustomerNotificationKind.orderUpdate) {
      return _NotificationIconInfo(
        ZopiqIconsFill.receipt,
        zc.primary,
      );
    }

    return _NotificationIconInfo(
      ZopiqIconsFill.bellRinging,
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
      // Null while selecting, so the row does not also mark itself read and
      // navigate away underneath the checkbox the customer just tapped.
      onTap: !tapsEnabled
          ? null
          : () {
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
                        icon: const Icon(ZopiqIcons.refresh, size: 18),
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


