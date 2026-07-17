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
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
        children: <Widget>[
          if (vendor != null) _Header(vendor: vendor),
          const SizedBox(height: ZopiqSpacing.sm),

          _Row(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Payments',
            subtitle: 'Earnings and weekly settlements',
            onTap: () => context.pushNamed(Routes.payments),
          ),
          _Row(
            icon: Icons.storefront_rounded,
            label: 'Restaurant profile',
            subtitle: 'Name, cuisines, price and offer',
            onTap: () => context.pushNamed(Routes.profile),
          ),

          const _SectionLabel('Coming soon'),
          const _Row(
            icon: Icons.insights_rounded,
            label: 'Analytics',
            subtitle: 'Sales, top dishes and trends',
          ),
          const _Row(
            icon: Icons.local_offer_rounded,
            label: 'Offers',
            subtitle: 'Run and track promotions',
          ),
          const _Row(
            icon: Icons.reviews_rounded,
            label: 'Reviews',
            subtitle: 'What customers are saying',
          ),
          const _Row(
            icon: Icons.notifications_rounded,
            label: 'Notifications',
            subtitle: 'Alerts and quiet hours',
          ),
          const _Row(
            icon: Icons.group_rounded,
            label: 'Staff',
            subtitle: 'Who can sign in to this kitchen',
          ),
          const _Row(
            icon: Icons.help_outline_rounded,
            label: 'Support',
            subtitle: 'Get help with your account',
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(vendorAuthControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        ZopiqSpacing.md,
        ZopiqSpacing.lg,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: zc.primary.withValues(alpha: 0.12),
            child: Icon(Icons.storefront_rounded, color: zc.primary),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  vendor.restaurantName,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
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
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        ZopiqSpacing.lg,
        ZopiqSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.zc.textMuted,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One hub row. A null [onTap] is the "coming soon" state — dimmed, with a small
/// tag, and no tap target.
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
    final Color ink = enabled ? zc.textStrong : zc.textMuted;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: enabled ? zc.primary : zc.textMuted),
      title: Text(
        label,
        style: t.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: enabled
          ? Icon(Icons.chevron_right_rounded, color: zc.textMuted)
          : Text(
              'Soon',
              style: t.labelSmall?.copyWith(color: zc.textMuted),
            ),
    );
  }
}
