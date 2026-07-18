import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/app/router.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/profile/domain/entities/restaurant_profile.dart';
import 'package:zopiq_vendor/features/profile/presentation/providers/profile_providers.dart';

/// The restaurant's own page: what customers see, and the door to editing it.
///
/// Read-mostly. The one thing a kitchen does here often is not on this screen at
/// all — pausing orders lives on the queue, where a busy cook already is. This is
/// where the slower changes happen: the name, the cuisines, the price.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Vendor? vendor = ref.watch(vendorProvider);
    final AsyncValue<RestaurantProfile> profile = ref.watch(
      restaurantProfileProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── Custom Header ──
            ZopiqReveal(
              index: 0,
              child: _Header(onSignOut: () => ref.read(vendorAuthControllerProvider.notifier).signOut()),
            ),

            Expanded(
              child: profile.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object _, StackTrace _) => _Error(
                  onRetry: () => ref.invalidate(restaurantProfileProvider),
                ),
                data: (RestaurantProfile p) => _ProfileView(profile: p, email: vendor?.email),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Restaurant Profile',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Your public storefront details',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: zc.nonVeg.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.logout_rounded, color: zc.nonVeg),
              tooltip: 'Sign out',
              onPressed: onSignOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.profile, this.email});

  final RestaurantProfile profile;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(
        left: ZopiqSpacing.pageGutter,
        right: ZopiqSpacing.pageGutter,
        bottom: ZopiqSpacing.xxl,
      ),
      children: <Widget>[
        if (profile.imageUrl.isNotEmpty) ...<Widget>[
          ZopiqReveal(
            index: 1,
            child: ClipRRect(
              borderRadius: ZopiqRadii.rLg,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ZopiqNetworkImage(
                  url: profile.imageUrl,
                  fallback: ColoredBox(color: zc.shimmerBase),
                ),
              ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
        ],
        
        ZopiqReveal(
          index: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  profile.name,
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: ZopiqSpacing.sm),
              _RatingPill(rating: profile.rating, count: profile.ratingCount),
            ],
          ),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        
        ZopiqReveal(
          index: 3,
          child: Wrap(
            spacing: ZopiqSpacing.sm,
            runSpacing: ZopiqSpacing.xs,
            children: <Widget>[
              for (final String c in profile.cuisines) _CuisineChip(label: c),
            ],
          ),
        ),
        const SizedBox(height: ZopiqSpacing.xl),

        ZopiqReveal(
          index: 4,
          child: ZopiqCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _FieldRow(
                  icon: Icons.payments_rounded,
                  label: 'Cost for two',
                  value: '₹${profile.priceForTwo}',
                ),
                const Divider(height: 1),
                _FieldRow(
                  icon: Icons.timer_rounded,
                  label: 'Prep time',
                  value: '${profile.etaMinutes} min',
                ),
                const Divider(height: 1),
                _FieldRow(
                  icon: profile.isVeg ? Icons.eco_rounded : Icons.restaurant_rounded,
                  label: 'Pure veg',
                  value: profile.isVeg ? 'Yes' : 'No',
                  iconColor: profile.isVeg ? zc.veg : zc.textMuted,
                ),
                const Divider(height: 1),
                _FieldRow(
                  icon: Icons.local_offer_rounded,
                  label: 'Offer',
                  value: profile.promoText ?? 'None',
                  muted: profile.promoText == null,
                ),
                if (email != null) ...<Widget>[
                  const Divider(height: 1),
                  _FieldRow(
                    icon: Icons.email_rounded,
                    label: 'Signed in as',
                    value: email!,
                    muted: true,
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: ZopiqSpacing.xl),
        
        ZopiqReveal(
          index: 5,
          child: ZopiqButton(
            label: 'Edit profile',
            icon: Icons.edit_rounded,
            onPressed: () => context.pushNamed(Routes.profileEdit),
          ),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        
        ZopiqReveal(
          index: 6,
          child: Text(
            'Your name, cuisines, price, offer and prep time show on the '
            'customer app. Ratings are earned and can\'t be edited.',
            style: t.bodySmall?.copyWith(color: zc.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.lg,
        vertical: ZopiqSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 20,
            color: iconColor ?? zc.textMuted,
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: Text(
              label,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
          ),
          Text(
            value,
            style: t.bodyMedium?.copyWith(
              color: muted ? zc.textMuted : zc.textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CuisineChip extends StatelessWidget {
  const _CuisineChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: zc.primary.withValues(alpha: 0.10),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: zc.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: zc.veg.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.star_rounded, size: 16, color: zc.veg),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            '${rating.toStringAsFixed(1)} ($count)',
            style: t.labelMedium?.copyWith(
              color: zc.veg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

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
            Icon(Icons.cloud_off_rounded, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text('We couldn\'t load your profile', style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              'Check the internet and try again.',
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
