import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/gifts/domain/entities/gift_item.dart';
import 'package:zopiqnow/features/gifts/presentation/widgets/gift_image.dart';

/// A single gift in the browse grid: an image with badges, category pill, name,
/// price, and quick action.
class GiftItemCard extends StatefulWidget {
  const GiftItemCard({required this.item, this.onTap, super.key});

  final GiftItem item;
  final VoidCallback? onTap;

  @override
  State<GiftItemCard> createState() => _GiftItemCardState();
}

class _GiftItemCardState extends State<GiftItemCard> {
  bool _isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
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
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Image with Stack for Badges & Favorite Heart
                Stack(
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: 1.05,
                      child: GiftImage(
                        url: widget.item.imageUrl,
                        seed: widget.item.id,
                      ),
                    ),
                    // Top Left: Gift Tag Badge
                    Positioned(
                      top: ZopiqSpacing.xs,
                      left: ZopiqSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZopiqSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: zc.primaryDeep.withValues(alpha: 0.9),
                          borderRadius: ZopiqRadii.rSm,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.card_giftcard_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Gift Boxed',
                              style: t.labelSmall?.copyWith(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Top Right: Favorite Button
                    Positioned(
                      top: ZopiqSpacing.xs,
                      right: ZopiqSpacing.xs,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isFavorite = !_isFavorite;
                          });
                        },
                        borderRadius: ZopiqRadii.rPill,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 15,
                            color: _isFavorite ? Colors.redAccent : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Card Details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(ZopiqSpacing.xs + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.item.category.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelSmall?.copyWith(
                                color: zc.primaryDeep,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              '₹${widget.item.price}',
                              style: t.titleMedium?.copyWith(
                                color: zc.textStrong,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ZopiqSpacing.xs + 2,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: zc.primaryDeep.withValues(alpha: 0.1),
                                borderRadius: ZopiqRadii.rPill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'View',
                                    style: t.labelSmall?.copyWith(
                                      color: zc.primaryDeep,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 9,
                                    color: zc.primaryDeep,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
