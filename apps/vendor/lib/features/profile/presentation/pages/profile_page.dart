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
      appBar: AppBar(
        title: const Text('Profile'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(vendorAuthControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => _Error(
          onRetry: () => ref.invalidate(restaurantProfileProvider),
        ),
        data: (RestaurantProfile p) => _ProfileView(profile: p, email: vendor?.email),
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
      padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
      children: <Widget>[
        if (profile.imageUrl.isNotEmpty) ...<Widget>[
          ClipRRect(
            borderRadius: ZopiqRadii.rMd,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ZopiqNetworkImage(
                url: profile.imageUrl,
                fallback: ColoredBox(color: zc.shimmerBase),
              ),
            ),
          ),
          const SizedBox(height: ZopiqSpacing.lg),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                profile.name,
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            _RatingPill(rating: profile.rating, count: profile.ratingCount),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.md),
        Wrap(
          spacing: ZopiqSpacing.sm,
          runSpacing: ZopiqSpacing.xs,
          children: <Widget>[
            for (final String c in profile.cuisines) _CuisineChip(label: c),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.xl),

        _Field(label: 'Cost for two', value: '₹${profile.priceForTwo}'),
        _Field(label: 'Prep time', value: '${profile.etaMinutes} min'),
        _Field(label: 'Pure veg', value: profile.isVeg ? 'Yes' : 'No'),
        _Field(
          label: 'Offer',
          value: profile.promoText ?? 'None',
          muted: profile.promoText == null,
        ),
        if (email != null) _Field(label: 'Signed in as', value: email!),

        const SizedBox(height: ZopiqSpacing.xl),
        ZopiqButton(
          label: 'Edit profile',
          icon: Icons.edit_rounded,
          onPressed: () => context.pushNamed(Routes.profileEdit),
        ),
        const SizedBox(height: ZopiqSpacing.md),
        Text(
          'Your name, cuisines, price, offer and prep time show on the '
          'customer app. Ratings are earned and can\'t be edited.',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: t.bodyLarge?.copyWith(
                color: muted ? zc.textMuted : zc.textStrong,
                fontWeight: FontWeight.w600,
              ),
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
              fontWeight: FontWeight.w700,
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
