import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// The fifth tab: everything that isn't the day-to-day of taking orders.
///
/// A hub, not a screen of its own content. The live destinations — the profile
/// and payments — sit at the top; the rooms the roadmap still owes (analytics,
/// offers, reviews, and the rest) are listed as coming so the shape of the app
/// is honest about where it is going, and greyed so nobody taps a dead end.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(
            left: ZopiqSpacing.pageGutter,
            right: ZopiqSpacing.pageGutter,
            bottom: ZopiqSpacing.xxl,
          ),
          children: <Widget>[
            // ── Custom Header ──
            const ZopiqReveal(
              index: 0,
              child: _Header(),
            ),

            if (vendor != null)
              ZopiqReveal(
                index: 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
                  child: _ProfileCard(vendor: vendor),
                ),
              ),

            ZopiqReveal(
              index: 2,
              child: _Row(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Payments',
                subtitle: 'Earnings and weekly settlements',
                onTap: () => context.pushNamed(Routes.payments),
              ),
            ),
            ZopiqReveal(
              index: 3,
              child: _Row(
                icon: Icons.storefront_rounded,
                label: 'Restaurant profile',
                subtitle: 'Name, cuisines, price and offer',
                onTap: () => context.pushNamed(Routes.profile),
              ),
            ),
            ZopiqReveal(
              index: 4,
              child: _Row(
                icon: Icons.schedule_rounded,
                label: 'Opening hours',
                subtitle: 'The days and times you take orders',
                onTap: () => context.pushNamed(Routes.hours),
              ),
            ),
            ZopiqReveal(
              index: 5,
              child: _Row(
                icon: Icons.insights_rounded,
                label: 'Analytics',
                subtitle: 'Sales, top dishes and trends',
                onTap: () => context.pushNamed(Routes.analytics),
              ),
            ),
            ZopiqReveal(
              index: 6,
              child: _Row(
                icon: Icons.help_outline_rounded,
                label: 'Support',
                subtitle: 'Answers, and how to reach us',
                onTap: () => context.pushNamed(Routes.support),
              ),
            ),

            const ZopiqReveal(
              index: 7,
              child: _SectionLabel('Coming soon'),
            ),
            const ZopiqReveal(
              index: 8,
              child: _Row(
                icon: Icons.local_offer_rounded,
                label: 'Offers',
                subtitle: 'Run and track promotions',
              ),
            ),
            const ZopiqReveal(
              index: 9,
              child: _Row(
                icon: Icons.reviews_rounded,
                label: 'Reviews',
                subtitle: 'What customers are saying',
              ),
            ),
            const ZopiqReveal(
              index: 10,
              child: _Row(
                icon: Icons.notifications_rounded,
                label: 'Notifications',
                subtitle: 'Alerts and quiet hours',
              ),
            ),
            const ZopiqReveal(
              index: 11,
              child: _Row(
                icon: Icons.group_rounded,
                label: 'Staff',
                subtitle: 'Who can sign in to this kitchen',
              ),
            ),
            
            const SizedBox(height: ZopiqSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(
        top: ZopiqSpacing.lg,
        bottom: ZopiqSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Settings & More',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Manage your account and preferences',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.storefront_rounded, color: zc.primary, size: 24),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  vendor.restaurantName,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  vendor.email,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.sm,
        ZopiqSpacing.xl,
        ZopiqSpacing.sm,
        ZopiqSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.zc.textMuted,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One hub row, redesigned as a ZopiqCard.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool enabled = onTap != null;
    final Color iconColor = enabled ? zc.primary : zc.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: ZopiqPressable(
        onTap: onTap,
        child: ZopiqCard(
          padding: const EdgeInsets.all(ZopiqSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: enabled ? 0.10 : 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled ? zc.textStrong : zc.textMuted,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      subtitle,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(Icons.chevron_right_rounded, color: zc.textMuted, size: 20)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: zc.textMuted.withValues(alpha: 0.1),
                    borderRadius: ZopiqRadii.rPill,
                  ),
                  child: Text(
                    'Soon',
                    style: t.labelSmall?.copyWith(
                      color: zc.textMuted,
                      fontWeight: FontWeight.w700,
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
