import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart'
    show restaurantImageHeroTag;
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart';

/// Collapsing menu header: the restaurant image, then its name and vitals.
class MenuSliverAppBar extends StatelessWidget {
  const MenuSliverAppBar({required this.restaurant, super.key});

  final Restaurant restaurant;

  static const double _expandedHeight = 220;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: _expandedHeight,
      backgroundColor: Theme.of(context).colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          restaurant.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        titlePadding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.xxxl + ZopiqSpacing.md,
          vertical: ZopiqSpacing.md,
        ),
        background: Hero(
          tag: restaurantImageHeroTag(restaurant.id),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RestaurantImage(restaurant: restaurant, iconSize: 48),
              // Keeps the collapsed title legible over any image.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      ZopiqPalette.black.withValues(alpha: 0),
                      ZopiqPalette.black.withValues(alpha: 0.55),
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

/// The vitals strip under the header: rating, delivery time, cost for two.
class MenuVitals extends StatelessWidget {
  const MenuVitals({required this.restaurant, super.key});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: ZopiqCard(
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.star_rounded, size: 18, color: zc.rating),
                const SizedBox(width: ZopiqSpacing.xxs),
                Text(
                  '${restaurant.rating.toStringAsFixed(1)} '
                  '(${restaurant.ratingCount}+ ratings)',
                  style: t.titleSmall,
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                Text('•', style: t.bodyMedium?.copyWith(color: zc.textMuted)),
                const SizedBox(width: ZopiqSpacing.sm),
                Flexible(
                  child: Text(
                    '₹${restaurant.priceForTwo} for two',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              restaurant.cuisines.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: zc.primary),
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.schedule_rounded, size: 16, color: zc.textMuted),
                const SizedBox(width: ZopiqSpacing.xs),
                Text(
                  '${restaurant.etaMinutes} min • '
                  '${restaurant.distanceKm.toStringAsFixed(1)} km away',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
