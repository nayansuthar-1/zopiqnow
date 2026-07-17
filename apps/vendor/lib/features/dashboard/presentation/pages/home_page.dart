import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_greeting()),
            Text(
              vendor?.restaurantName ?? 'Zopiqnow Partner',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.zc.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          if (vendor != null) _StoreStatusCard(vendor: vendor),
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'Today',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
          const _WeeklyEarningsCard(),
          const SizedBox(height: ZopiqSpacing.xl),
          Text(
            'Shortcuts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.md),
          const _Shortcuts(),
        ],
      ),
    );
  }

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// The open/closed switch, on Home as well as the queue — an owner opening for
/// the day starts here, not on the worklist. Optimistic, like the queue's: the
/// switch flips first and the write confirms it, because a kitchen must never be
/// made to wait on a round trip to reopen.
class _StoreStatusCard extends ConsumerWidget {
  const _StoreStatusCard({required this.vendor});

  final Vendor vendor;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool open) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? error = await ref
        .read(vendorAuthControllerProvider.notifier)
        .setAcceptingOrders(open);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool open = vendor.acceptingOrders;
    final Color accent = open ? zc.veg : zc.nonVeg;

    return ZopiqCard(
      child: Row(
        children: <Widget>[
          Icon(
            open ? Icons.storefront_rounded : Icons.no_meals_rounded,
            color: accent,
            size: 26,
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  open ? 'Taking orders' : 'Orders paused',
                  style: t.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  open
                      ? 'Customers can order from you now.'
                      : 'You won\'t receive new orders until you reopen.',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: open,
            activeTrackColor: zc.veg,
            onChanged: (bool value) => _toggle(context, ref, value),
          ),
        ],
      ),
    );
  }
}

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
              child: _StatTile(
                icon: Icons.receipt_long_rounded,
                label: 'Orders today',
                value: '${stats.orders}',
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: _StatTile(
                icon: Icons.payments_rounded,
                label: 'Revenue today',
                value: formatRupees(stats.revenue),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatTile(
                icon: Icons.pending_actions_rounded,
                label: 'In the queue',
                value: '${stats.inQueue}',
                highlight: stats.newOrders > 0,
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: _StatTile(
                icon: Icons.done_all_rounded,
                label: 'Delivered today',
                value: '${stats.delivered}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Draws the count in the brand colour — used when there are new orders
  /// waiting, so "3 in the queue" pulls the eye the way an idle "0" should not.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: const EdgeInsets.all(ZopiqSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: zc.textMuted),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(
            value,
            style: t.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: highlight ? zc.primary : zc.textStrong,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(label, style: t.bodySmall?.copyWith(color: zc.textMuted)),
        ],
      ),
    );
  }
}

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'This week\'s earnings',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: zc.textMuted),
            ],
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
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
                Text(
                  formatRupees(e.netEarnings),
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                  ),
                ),
                if (e.daily.isNotEmpty) ...<Widget>[
                  const SizedBox(height: ZopiqSpacing.md),
                  SizedBox(
                    height: 56,
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

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _Shortcut(
            icon: Icons.restaurant_menu_rounded,
            label: 'Menu',
            onTap: () => context.goNamed(Routes.menu),
          ),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: _Shortcut(
            icon: Icons.history_rounded,
            label: 'History',
            onTap: () => context.goNamed(Routes.history),
          ),
        ),
        const SizedBox(width: ZopiqSpacing.md),
        Expanded(
          child: _Shortcut(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Payments',
            onTap: () => context.goNamed(Routes.payments),
          ),
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Icon(icon, color: zc.primary),
          const SizedBox(height: ZopiqSpacing.sm),
          Text(
            label,
            style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
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
