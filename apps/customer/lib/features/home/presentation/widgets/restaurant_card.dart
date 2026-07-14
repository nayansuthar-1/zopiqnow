import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/favourites/presentation/widgets/favourite_button.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart';

/// Hero tag shared by a restaurant's Home list card and its menu header, so the
/// image flies between the two screens.
///
/// Lives here, next to the card that owns the source Hero, so the menu feature
/// depends on home rather than the reverse.
String restaurantImageHeroTag(String restaurantId) =>
    'restaurant-image-$restaurantId';

/// Dark green used for rating pill and veg indicators — matches the reference
/// design (Swiggy-style deep green, not the lighter token).
const Color _darkGreen = Color(0xFF267335);

/// Discovery card for a single [Restaurant]. Pure presentation — all spacing
/// and radius come from zopiq_ui tokens.
///
/// Redesigned to match the Swiggy-style reference:
/// - Thin border with low opacity
/// - Cuisine · price overlay badge (top-left of image)
/// - Favourite heart (top-right of image) — a live control now. It was a
///   decorative bookmark glyph: an icon that looked tappable, was not, and did
///   nothing, which is the worst thing a control can be.
/// - "FREE delivery" badge (bottom-left of image)
/// - Dot indicator (bottom-right of image)
/// - Name + dark-green rating pill
/// - ETA | distance row
/// - Offer text
/// - Dashed divider + "Pure Veg restaurant" footer
class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    required this.restaurant,
    this.onTap,
    this.heroic = true,
    super.key,
  });

  final Restaurant restaurant;
  final VoidCallback? onTap;

  /// Whether this card's image is the Hero source for the menu header.
  ///
  /// Exactly one mounted card per restaurant may claim it. Home and Search both
  /// live in the shell's `IndexedStack` — both mounted, one Navigator — so a
  /// restaurant showing in both would register two Heroes under one tag and
  /// crash the next route transition. Search therefore opts out; it loses the
  /// image flight, not the navigation.
  final bool heroic;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: ZopiqRadii.rXl,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: ZopiqRadii.rXl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CardImage(restaurant: restaurant, heroic: heroic),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.lg,
                  vertical: ZopiqSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // ─── Name + rating ───
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            restaurant.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZopiqSpacing.sm),
                        _RatingPill(rating: restaurant.rating),
                      ],
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),

                    // ─── ETA | distance ───
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.schedule_outlined,
                          size: 16,
                          color: zc.textMuted,
                        ),
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          '${restaurant.etaMinutes} min',
                          style: t.bodyMedium?.copyWith(color: zc.textMuted),
                        ),
                        _Separator(color: zc.textMuted),
                        Text(
                          '${restaurant.distanceKm.toStringAsFixed(1)} km',
                          style: t.bodyMedium?.copyWith(color: zc.textMuted),
                        ),
                      ],
                    ),

                    // ─── Offer text ───
                    if (restaurant.promoText != null) ...<Widget>[
                      const SizedBox(height: ZopiqSpacing.sm),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.local_offer_rounded,
                            size: 16,
                            color: Color(0xFF5B8DF5),
                          ),
                          const SizedBox(width: ZopiqSpacing.xs),
                          Flexible(
                            child: Text(
                              restaurant.promoText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: zc.textStrong,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ─── Pure Veg footer (only if veg) ───
              if (restaurant.isVeg) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.lg,
                  ),
                  child: _DashedDivider(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: ZopiqSpacing.lg,
                    right: ZopiqSpacing.lg,
                    top: ZopiqSpacing.sm,
                    bottom: ZopiqSpacing.md,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZopiqSpacing.md,
                      vertical: ZopiqSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF5F5F5),
                      borderRadius: ZopiqRadii.rPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Leaf-style veg icon
                        const Icon(
                          Icons.eco_rounded,
                          size: 16,
                          color: _darkGreen,
                        ),
                        const SizedBox(width: ZopiqSpacing.xs),
                        Text(
                          'Pure Veg restaurant',
                          style: t.labelMedium?.copyWith(
                            color: zc.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.restaurant, required this.heroic});

  final Restaurant restaurant;
  final bool heroic;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Widget image = RestaurantImage(restaurant: restaurant);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ZopiqRadii.xl),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Image (with optional Hero animation)
            if (heroic)
              Hero(tag: restaurantImageHeroTag(restaurant.id), child: image)
            else
              image,

            // ─── Favourite heart (top-right) ───
            // Outside the card's InkWell hit area in intent, though not in the
            // tree: it takes its own tap, so hearting a restaurant does not also
            // open its menu.
            Positioned(
              right: ZopiqSpacing.md,
              top: ZopiqSpacing.md,
              child: FavouriteButton(restaurant: restaurant),
            ),

            // ─── Cuisine · Price overlay (top-left) ───
            Positioned(
              left: ZopiqSpacing.md,
              top: ZopiqSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.sm + 2,
                  vertical: ZopiqSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: ZopiqRadii.rSm,
                ),
                child: Text(
                  '${restaurant.cuisines.take(1).join()} · ₹${restaurant.priceForTwo} for one',
                  style: t.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // ─── "FREE delivery" badge (bottom-left) ───
            Positioned(
              left: 0,
              bottom: ZopiqSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.md,
                  vertical: ZopiqSpacing.xs,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(ZopiqRadii.xs),
                    bottomRight: Radius.circular(ZopiqRadii.xs),
                  ),
                ),
                child: Text(
                  'FREE delivery',
                  style: t.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),

            // ─── Dot indicator strip (bottom-right) ───
            Positioned(
              right: ZopiqSpacing.md,
              bottom: ZopiqSpacing.md,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(5, (int i) {
                  return Container(
                    width: 6,
                    height: 6,
                    margin: EdgeInsets.only(
                      left: i == 0 ? 0 : ZopiqSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rating.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.xxs),
          const Icon(Icons.star_rounded, size: 14, color: Colors.white),
        ],
      ),
    );
  }
}

/// Vertical pipe separator between inline metadata items.
class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.sm),
      child: Container(
        width: 1,
        height: 14,
        color: color.withValues(alpha: 0.35),
      ),
    );
  }
}

/// A dashed horizontal divider drawn with a [CustomPainter].
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashPainter(color: color),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double dashWidth = 5;
    const double dashSpace = 3;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => color != oldDelegate.color;
}
