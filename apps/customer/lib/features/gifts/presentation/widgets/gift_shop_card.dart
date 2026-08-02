import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_shop.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// A gift shop card in the storefront rail:
/// Inspired by Blinkit's partner studio cards with verified badges, rating pills,
/// cover gradient scrim, and studio taglines.
class GiftShopCard extends StatelessWidget {
  const GiftShopCard({required this.shop, this.onTap, super.key});

  final GiftShop shop;
  final VoidCallback? onTap;

  /// Fixed width so the rail scrolls horizontally smoothly.
  static const double cardWidth = 240;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: cardWidth,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE8ECEF),
            width: 1.0,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
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
                      // Scrim
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.black.withValues(alpha: 0.3),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.25),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Top Left Verified Pill
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.workspace_premium_rounded,
                                size: 12,
                                color: Color(0xFFFFD700),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'VERIFIED STUDIO',
                                style: t.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
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
                                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                                ),
                              ),
                            ),
                            if (shop.rating != null) ...<Widget>[
                              const SizedBox(width: 6),
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
                            fontSize: 11.5,
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

/// Blinkit signature green rating pill.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final double rating;

  static const Color _blinkitGreen = Color(0xFF0C831F);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: _blinkitGreen,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 10, color: Colors.white),
        ],
      ),
    );
  }
}

