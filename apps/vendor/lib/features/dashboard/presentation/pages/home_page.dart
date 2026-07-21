import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/store_status_banner.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/notifications/presentation/providers/notifications_providers.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/payments/domain/entities/earnings_summary.dart';
import 'package:zopiq_vendor/features/payments/presentation/providers/payments_providers.dart';
import 'package:zopiq_vendor/features/payments/presentation/widgets/earnings_bar_chart.dart';

/// The first room of the app — the day at a glance.
///
/// Not a worklist: that is the Orders tab, one tap away. Home answers the
/// questions a manager asks before they roll their sleeves up — are we open, how
/// has today gone, and what are we owed — and hands off to the screen that acts
/// on each. A cook mid-rush never has to come here; an owner starts here.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);
    final AsyncValue<List<VendorOrder>> ordersAsync = ref.watch(ordersProvider);
    final TodayStats stats = ref.watch(todayStatsProvider);
    final bool isOwner = vendor?.role.isOwner ?? false;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: context.zc.primary,
          onRefresh: () async {
            ref.invalidate(ordersProvider);
            ref.invalidate(earningsProvider(EarningsRange.last7));
            // A brief pause so the indicator is visible — an instant dismiss
            // makes the pull feel like it did nothing.
            await Future<void>.delayed(const Duration(milliseconds: 400));
          },
          child: ListView(
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.pageGutter,
            ),
            children: <Widget>[
              const SizedBox(height: ZopiqSpacing.lg),

              // ── 1. Header ──
              ZopiqReveal(
                index: 0,
                child: _Header(vendor: vendor),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              // ── 2. Store Status Banner ──
              if (vendor != null)
                ZopiqReveal(
                  index: 1,
                  child: StoreStatusBanner(vendor: vendor),
                ),
              const SizedBox(height: ZopiqSpacing.xl),

              // ── 6. Active Orders Preview (above today stats) ──
              if (stats.inQueue > 0)
                ZopiqReveal(
                  index: 2,
                  child: _ActiveOrdersCard(stats: stats),
                ),
              if (stats.inQueue > 0)
                const SizedBox(height: ZopiqSpacing.xl),

              // ── 3. Today's Performance ──
              const ZopiqReveal(
                index: 3,
                child: _SectionHeader(title: "Today's Performance"),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              ordersAsync.when(
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object _, StackTrace _) => _TodayError(
                  onRetry: () => ref.invalidate(ordersProvider),
                ),
                data: (_) => _TodayGrid(stats: stats),
              ),
              const SizedBox(height: ZopiqSpacing.xl),

              // ── 4. Weekly Earnings ── owner's, like the Payments screen it
              // opens (0024). Staff get today's revenue in the grid above, which
              // is the shift they are working; the week's take is the business's.
              if (isOwner) ...<Widget>[
                const ZopiqReveal(
                  index: 5,
                  child: _WeeklyEarningsCard(),
                ),
                const SizedBox(height: ZopiqSpacing.xl),
              ],

              // ── 5. Quick Actions ──
              const ZopiqReveal(
                index: 6,
                child: _SectionHeader(title: 'Quick Actions'),
              ),
              const SizedBox(height: ZopiqSpacing.md),
              ZopiqReveal(
                index: 6,
                child: _QuickActions(isOwner: isOwner),
              ),
              const SizedBox(height: ZopiqSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.vendor});

  final Vendor? vendor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final String name = vendor?.restaurantName ?? 'Zopiqnow Partner';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : 'Z';

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                style: t.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: zc.textStrong,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ZopiqSpacing.xxs),
              Text(
                '${_greeting()} · ${_formattedDate()}',
                style: t.bodyMedium?.copyWith(
                  color: zc.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: ZopiqSpacing.sm),
        const _NotificationBell(),
        const SizedBox(width: ZopiqSpacing.sm),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: zc.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: t.titleLarge?.copyWith(
              color: zc.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _formattedDate() {
    const List<String> days = <String>[
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final DateTime now = DateTime.now();
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }
}

/// The header bell — a quiet count of what's unread, and the way into the inbox.
///
/// `goNamed`, like the Quick Actions: it builds the More → Notifications stack,
/// so the bottom nav follows to More and Back returns to the hub.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final int unread = ref.watch(unreadCountProvider);

    return ZopiqPressable(
      onTap: () => context.goNamed(Routes.notifications),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: zc.textMuted.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: zc.textStrong,
                size: 22,
              ),
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  decoration: BoxDecoration(
                    color: zc.primary,
                    borderRadius: ZopiqRadii.rPill,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// 3. Today's Performance — stat tiles with accent bars & animated values
// ─────────────────────────────────────────────────────────────────────────────

class _TodayGrid extends StatelessWidget {
  const _TodayGrid({required this.stats});

  final TodayStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ZopiqReveal(
                index: 3,
                child: _StatCard(
                  icon: Icons.receipt_long_rounded,
                  label: 'Orders today',
                  value: '${stats.orders}',
                  accentColor: context.zc.primary,
                ),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: ZopiqReveal(
                index: 3,
                child: _StatCard(
                  icon: Icons.payments_rounded,
                  label: 'Revenue today',
                  value: formatRupees(stats.revenue),
                  accentColor: context.zc.veg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: ZopiqReveal(
                index: 4,
                child: _StatCard(
                  icon: Icons.pending_actions_rounded,
                  label: 'In the queue',
                  value: '${stats.inQueue}',
                  accentColor: const Color(0xFF3B82F6), // clean blue
                  highlight: stats.newOrders > 0,
                ),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: ZopiqReveal(
                index: 4,
                child: _StatCard(
                  icon: Icons.done_all_rounded,
                  label: 'Delivered today',
                  value: '${stats.delivered}',
                  accentColor: context.zc.veg,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  /// Draws the count in the brand colour — used when there are new orders
  /// waiting, so "3 in the queue" pulls the eye the way an idle "0" should not.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Accent bar at top
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ZopiqRadii.lg),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.lg,
              ZopiqSpacing.md,
              ZopiqSpacing.lg,
              ZopiqSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Icon in a tinted circle
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
                const SizedBox(height: ZopiqSpacing.md),
                Text(
                  value,
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: highlight ? zc.primary : zc.textStrong,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  label,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Weekly Earnings Card
// ─────────────────────────────────────────────────────────────────────────────

/// The week's take, peeked at from Home and opened in full on Payments.
class _WeeklyEarningsCard extends ConsumerWidget {
  const _WeeklyEarningsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final AsyncValue<EarningsSummary> earnings = ref.watch(
      earningsProvider(EarningsRange.last7),
    );

    return ZopiqCard(
      onTap: () => context.goNamed(Routes.payments),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header row
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  size: 16,
                  color: zc.primary,
                ),
              ),
              const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: Text(
                  'This Week',
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: zc.textStrong,
                  ),
                ),
              ),
              Text(
                'View All',
                style: t.labelMedium?.copyWith(
                  color: zc.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: ZopiqSpacing.xxs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: zc.primary,
              ),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.md),
          Divider(height: 1, color: zc.divider),
          const SizedBox(height: ZopiqSpacing.md),

          // Earnings amount
          earnings.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object _, StackTrace _) => Text(
              'Earnings unavailable',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
            data: (EarningsSummary e) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ZopiqAnimatedAmount(
                  amount: e.netEarnings,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                  ),
                ),
                if (e.orderCount > 0) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    '${e.orderCount} orders · ${(e.commissionPercent).toStringAsFixed(0)}% commission',
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
                if (e.daily.isNotEmpty) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.lg),
                  SizedBox(
                    height: 72,
                    child: EarningsBarChart(daily: e.daily, compact: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Quick Actions
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.isOwner});

  /// Payments is the owner's shortcut only — the row falls back to three tiles
  /// for everyone else rather than offering a door the database would shut.
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickActionTile(
            icon: Icons.restaurant_menu_rounded,
            label: 'Menu',
            color: const Color(0xFFEF4444), // warm red
            onTap: () => context.goNamed(Routes.menu),
          ),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.history_rounded,
            label: 'History',
            color: const Color(0xFF8B5CF6), // purple
            onTap: () => context.goNamed(Routes.history),
          ),
        ),
        if (isOwner) ...<Widget>[
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: _QuickActionTile(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Payments',
              color: const Color(0xFF10B981), // emerald green
              onTap: () => context.goNamed(Routes.payments),
            ),
          ),
        ],
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.bar_chart_rounded,
            label: 'Analytics',
            color: const Color(0xFF3B82F6), // clean blue
            onTap: () => context.goNamed(Routes.analytics),
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqPressable(
      onTap: onTap,
      child: ZopiqCard(
        padding: const EdgeInsets.symmetric(
          vertical: ZopiqSpacing.lg,
          horizontal: ZopiqSpacing.sm,
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              label,
              style: t.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Active Orders Preview
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveOrdersCard extends StatelessWidget {
  const _ActiveOrdersCard({required this.stats});

  final TodayStats stats;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqPressable(
      onTap: () => context.goNamed(Routes.queue),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: ZopiqRadii.rLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: <Widget>[
              // Left accent strip
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: zc.primary,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(ZopiqRadii.lg),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(ZopiqSpacing.lg),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: zc.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                          color: zc.primary,
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${stats.inQueue} ${stats.inQueue == 1 ? 'order' : 'orders'} in the kitchen',
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: zc.textStrong,
                              ),
                            ),
                            if (stats.newOrders > 0) ...<Widget>[
                              const SizedBox(height: ZopiqSpacing.xxs),
                              Row(
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ZopiqSpacing.sm,
                                      vertical: ZopiqSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: zc.primary.withValues(alpha: 0.12),
                                      borderRadius: ZopiqRadii.rPill,
                                    ),
                                    child: Text(
                                      '${stats.newOrders} new',
                                      style: t.labelSmall?.copyWith(
                                        color: zc.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: ZopiqSpacing.sm),
                                  Text(
                                    'Tap to view queue',
                                    style: t.bodySmall?.copyWith(
                                      color: zc.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: zc.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// A clean section header with label.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Text(
      title,
      style: t.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TodayError extends StatelessWidget {
  const _TodayError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, color: zc.textMuted),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Text(
              'Today\'s numbers can\'t reach you right now.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
