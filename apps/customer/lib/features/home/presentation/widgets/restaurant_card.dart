import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// Discovery card for a single [Restaurant]. Pure presentation — all color,
/// spacing, radius, and type come from zopiq_ui tokens (Rule 2).
class RestaurantCard extends StatelessWidget {
  const RestaurantCard({required this.restaurant, this.onTap, super.key});

  final Restaurant restaurant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardImage(restaurant: restaurant),
          Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ZopiqVegIndicator(isVeg: restaurant.isVeg),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Expanded(
                      child: Text(
                        restaurant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium,
                      ),
                    ),
                    const SizedBox(width: ZopiqSpacing.sm),
                    _RatingPill(rating: restaurant.rating, color: zc.rating),
                  ],
                ),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  restaurant.cuisines.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
                const SizedBox(height: ZopiqSpacing.sm),
                Row(
                  children: <Widget>[
                    Icon(Icons.schedule_rounded, size: 14, color: zc.textMuted),
                    const SizedBox(width: ZopiqSpacing.xxs),
                    Text('${restaurant.etaMinutes} min', style: t.labelMedium),
                    _Dot(color: zc.textMuted),
                    Text('₹${restaurant.priceForTwo} for two', style: t.labelMedium),
                    _Dot(color: zc.textMuted),
                    Text(
                      '${restaurant.distanceKm.toStringAsFixed(1)} km',
                      style: t.labelMedium?.copyWith(color: zc.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    // Deterministic tint from the id so cards feel distinct until real
    // CDN images land (TODO: swap for a cached network image).
    final double hue = (restaurant.id.hashCode % 360).abs().toDouble();
    final Color tint = HSLColor.fromAHSL(1, hue, 0.35, 0.55).toColor();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(ZopiqRadii.lg)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[tint, tint.withValues(alpha: 0.75)],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.restaurant_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 40,
                ),
              ),
            ),
            if (restaurant.promoText != null)
              Positioned(
                left: ZopiqSpacing.sm,
                bottom: ZopiqSpacing.sm,
                child: _PromoBadge(text: restaurant.promoText!, color: zc.primaryDeep),
              ),
            Positioned(
              top: ZopiqSpacing.sm,
              right: ZopiqSpacing.sm,
              child: Container(
                padding: const EdgeInsets.all(ZopiqSpacing.xs),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.favorite_border_rounded, size: 18, color: zc.nonVeg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(color: color, borderRadius: ZopiqRadii.rXs),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, required this.color});

  final double rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(color: color, borderRadius: ZopiqRadii.rXs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 14, color: Colors.white),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.sm),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
