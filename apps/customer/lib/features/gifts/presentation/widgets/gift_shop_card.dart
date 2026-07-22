import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// A gift shop in the storefront rail: cover image with verified badge, title, tagline, and rating pill.
class GiftShopCard extends StatelessWidget {
  const GiftShopCard({required this.shop, this.onTap, super.key});

  final GiftShop shop;
  final VoidCallback? onTap;

  /// Fixed width so the rail scrolls horizontally with consistent cards.
  static const double cardWidth = 230;

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
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            width: 1.0,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: ZopiqRadii.rLg,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GiftImage(
                          url: shop.imageUrl,
                          seed: shop.id,
                          icon: Icons.storefront_rounded,
                        ),
                      ),
                      Positioned(
                        top: ZopiqSpacing.xs,
                        left: ZopiqSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZopiqSpacing.xs + 2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: ZopiqRadii.rSm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.verified_rounded,
                                size: 12,
                                color: Color(0xFFFFD700),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Verified Studio',
                                style: t.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (shop.rating != null) ...<Widget>[
                              const SizedBox(width: ZopiqSpacing.xs),
                              _RatingPill(rating: shop.rating!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          shop.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(
                            color: zc.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark-green rating pill.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final double rating;

  static const Color _darkGreen = Color(0xFF267335);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.xs + 2,
        vertical: 2,
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
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 11, color: Colors.white),
        ],
      ),
    );
  }
}
