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

  static const double _cardWidth = 112;
  static const double _imageHeight = 112;
  static const double _cardHeight = 180;
  static const double _railHeight = (_cardHeight * 2) + ZopiqSpacing.md;

  /// Below this the rail stops being a rail.
  ///
  /// Two 112pt cards pinned to the left of a 360pt screen, under a heading, read
  /// as a section that failed to finish loading — there is nothing to scroll and
  /// most of the row is empty. So one or two restaurants widen to fill it
  /// instead, which is a deliberate layout rather than an accident of how few
  /// there are. A category page hits this constantly; Home rarely does.
  static const int _minimumForRail = 3;

  @override
  Widget build(BuildContext context) {
    final List<Restaurant> items = restaurants.take(8).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    if (items.length < _minimumForRail) {
      return Padding(
        padding: ZopiqSpacing.pagePadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: _ChainCard(
                  restaurant: items[i],
                  onTap: onTapRestaurant == null
                      ? null
                      : () => onTapRestaurant!(items[i]),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: _railHeight,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: ZopiqSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: ZopiqSpacing.md,
          crossAxisSpacing: ZopiqSpacing.md,
          mainAxisExtent: _cardWidth,
        ),
        itemBuilder: (BuildContext context, int i) => RepaintBoundary(
          child: _ChainCard(
            restaurant: items[i],
            width: _cardWidth,
            onTap: onTapRestaurant == null
                ? null
                : () => onTapRestaurant!(items[i]),
          ),
        ),
      ),
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.restaurant, this.width, this.onTap});

  final Restaurant restaurant;

  /// Fixed in the rail, null when the card is sharing a row — a null width on
  /// [SizedBox] imposes no constraint, so the card takes whatever the `Expanded`
  /// above it hands down.
  final double? width;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqPressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          // The rail gives each cell a fixed 180pt; a shared row gives unbounded
          // height, and a `max` Column in unbounded height is a layout error.
          mainAxisSize: MainAxisSize.min,
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
