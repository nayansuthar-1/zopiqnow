import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// A gift shop in the storefront rail: a wide cover, the name, tagline, and a
/// rating pill. Tapping opens the shop's storefront page.
class GiftShopCard extends StatelessWidget {
  const GiftShopCard({required this.shop, this.onTap, super.key});

  final GiftShop shop;
  final VoidCallback? onTap;

  /// Fixed width so the rail scrolls horizontally with consistent cards.
  static const double cardWidth = 220;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: cardWidth,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: ZopiqRadii.rLg,
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: ZopiqRadii.rLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(ZopiqRadii.lg),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: GiftImage(
                      url: shop.imageUrl,
                      seed: shop.id,
                      icon: Icons.storefront_rounded,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(ZopiqSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              shop.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (shop.rating != null) ...<Widget>[
                            const SizedBox(width: ZopiqSpacing.sm),
                            _RatingPill(rating: shop.rating!),
                          ],
                        ],
                      ),
                      const SizedBox(height: ZopiqSpacing.xxs),
                      Text(
                        shop.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark-green rating pill, matching the restaurant card's.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final double rating;

  static const Color _darkGreen = Color(0xFF267335);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: _darkGreen,
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.xxs),
          const Icon(Icons.star_rounded, size: 12, color: Colors.white),
        ],
      ),
    );
  }
}
