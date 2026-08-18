import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
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
    // What the restaurant earns, and who may sign in to it, are the owner's
    // (migration 0024). The rows are absent rather than greyed: a "Soon" chip
    // says the app owes you this, and a disabled row says you personally may
    // not — which is a thing to tell someone plainly, in one place, not to
    // sprinkle across a hub. Hiding them decides nothing on its own; the
    // policies and RPCs refuse a non-owner regardless of what is drawn here.
    final bool isOwner = vendor?.role.isOwner ?? false;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(
            left: ZopiqSpacing.pageGutter,
            right: ZopiqSpacing.pageGutter,
            bottom: ZopiqSpacing.xxl,
          ),
          children: <Widget>[
            const VendorFadeSlide(
              child: _Header(),
            ),

            if (vendor != null)
              VendorFadeSlide(
                delay: const Duration(milliseconds: 50),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
                  child: _ProfileCard(vendor: vendor),
                ),
              ),

            if (isOwner)
              VendorFadeSlide(
                delay: const Duration(milliseconds: 100),
                child: _Row(
                  svgType: VendorSvgType.earningsChart,
                  label: 'Payments',
                  subtitle: 'Earnings and weekly settlements',
                  onTap: () => context.pushNamed(Routes.payments),
                ),
              ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 120),
              child: _Row(
                svgType: VendorSvgType.storefront,
                label: 'Restaurant profile',
                subtitle: 'Name, cuisines, price and offer',
                onTap: () => context.pushNamed(Routes.profile),
              ),
            ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 140),
              child: _Row(
                svgType: VendorSvgType.prepTimer,
                label: 'Opening hours',
                subtitle: 'The days and times you take orders',
                onTap: () => context.pushNamed(Routes.hours),
              ),
            ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 160),
              child: _Row(
                svgType: VendorSvgType.earningsChart,
                label: 'Analytics',
                subtitle: 'Sales, top dishes and trends',
                onTap: () => context.pushNamed(Routes.analytics),
              ),
            ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 180),
              child: _Row(
                svgType: VendorSvgType.liveOrders,
                label: 'Notifications',
                subtitle: 'New orders and updates',
                onTap: () => context.pushNamed(Routes.notifications),
              ),
            ),
            if (isOwner)
              VendorFadeSlide(
                delay: const Duration(milliseconds: 200),
                child: _Row(
                  svgType: VendorSvgType.staffRoster,
                  label: 'Team',
                  subtitle: 'Who can sign in to this kitchen',
                  onTap: () => context.pushNamed(Routes.staff),
                ),
              ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 220),
              child: _Row(
                svgType: VendorSvgType.verifiedCheck,
                label: 'Support',
                subtitle: 'Answers, and how to reach us',
                onTap: () => context.pushNamed(Routes.support),
              ),
            ),

            VendorFadeSlide(
              delay: const Duration(milliseconds: 240),
              child: _Row(
                svgType: VendorSvgType.chefMenu,
                label: 'Offers',
                subtitle: 'Run and track promotions',
                onTap: () => context.pushNamed(Routes.offers),
              ),
            ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 260),
              child: _Row(
                svgType: VendorSvgType.verifiedCheck,
                label: 'Reviews',
                subtitle: 'What customers are saying',
                onTap: () => context.pushNamed(Routes.reviews),
              ),
            ),
            VendorFadeSlide(
              delay: const Duration(milliseconds: 280),
              child: _Row(
                svgType: VendorSvgType.verifiedCheck,
                label: 'Legal & policies',
                subtitle: 'The terms, the SLA, and how you get paid',
                onTap: () => context.pushNamed(Routes.legal),
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
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.sm),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rMd,
            ),
            child: VendorSvgIcon(
              type: VendorSvgType.moreGrid,
              size: 24,
              color: zc.primary,
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
            child: Center(
              child: VendorSvgIcon(
                type: VendorSvgType.storefront,
                size: 24,
                color: zc.primary,
              ),
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  vendor.restaurantName,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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


/// One hub row, redesigned as a ZopiqCard.
class _Row extends StatelessWidget {
  const _Row({
    required this.svgType,
    required this.label,
    required this.subtitle,
    this.onTap,
  });

  final VendorSvgType svgType;
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
                child: Center(
                  child: VendorSvgIcon(
                    type: svgType,
                    size: 20,
                    color: iconColor,
                  ),
                ),
              ),
              const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
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
                      fontWeight: FontWeight.bold,
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
