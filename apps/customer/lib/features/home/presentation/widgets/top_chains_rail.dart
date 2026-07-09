import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart';

/// "Top restaurant chains" — a horizontal rail of compact restaurant cards.
class TopChainsRail extends StatelessWidget {
  const TopChainsRail({
    required this.restaurants,
    this.onTapRestaurant,
    super.key,
  });

  final List<Restaurant> restaurants;
  final ValueChanged<Restaurant>? onTapRestaurant;

  static const double _cardWidth = 156;
  static const double _imageHeight = 156;
  static const double _railHeight = 244;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: ZopiqSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        itemCount: restaurants.length,
        separatorBuilder: (_, _) => const SizedBox(width: ZopiqSpacing.md),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: _ChainCard(
            restaurant: restaurants[i],
            onTap: onTapRestaurant == null
                ? null
                : () => onTapRestaurant!(restaurants[i]),
          ),
        ),
      ),
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.restaurant, this.onTap});

  final Restaurant restaurant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqPressable(
      onTap: onTap,
      child: SizedBox(
        width: TopChainsRail._cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ChainImage(restaurant: restaurant),
            const SizedBox(height: ZopiqSpacing.sm),
            Text(
              restaurant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleSmall,
            ),
            const SizedBox(height: ZopiqSpacing.xxs),
            Row(
              children: <Widget>[
                Icon(Icons.star_rounded, size: 14, color: zc.rating),
                const SizedBox(width: ZopiqSpacing.xxs),
                Flexible(
                  child: Text(
                    '${restaurant.rating.toStringAsFixed(1)} • ${restaurant.etaMinutes} min',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelMedium?.copyWith(color: zc.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xxs),
            Text(
              restaurant.cuisines.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainImage extends StatelessWidget {
  const _ChainImage({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: ZopiqRadii.rMd,
      child: SizedBox(
        height: TopChainsRail._imageHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RestaurantImage(restaurant: restaurant, iconSize: 36),
            if (restaurant.promoText != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PromoStrip(text: restaurant.promoText!),
              ),
          ],
        ),
      ),
    );
  }
}

class _PromoStrip extends StatelessWidget {
  const _PromoStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            ZopiqPalette.black.withValues(alpha: 0),
            ZopiqPalette.black.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: ZopiqPalette.white),
      ),
    );
  }
}
