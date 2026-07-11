import 'package:flutter/material.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// Circular tile holding one dish category's 3D artwork.
///
/// [FoodCategory.imageAsset] is the seam. The bundled art is **Microsoft Fluent
/// Emoji (3D)** — MIT licensed, see ATTRIBUTIONS.md — swappable for commissioned
/// renders by changing the file. A tinted glyph shows only if an asset is ever
/// missing, so the rail never renders a blank tile.
class CategoryArt extends StatelessWidget {
  const CategoryArt({required this.category, required this.size, super.key});

  final FoodCategory category;
  final double size;

  /// Inset of the artwork inside the disc, as a fraction of [size]. The 3D
  /// renders read best nearly filling the tile, with a little breathing room.
  static const double _insetFactor = 0.14;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final String? asset = category.imageAsset;
    final double inset = size * _insetFactor;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHigh,
          // A soft lift so each 3D render sits on a tactile chip, not flat on
          // the background.
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.05),
            ),
          ],
        ),
        child: asset == null
            ? Center(
                child: Icon(
                  Icons.restaurant_rounded,
                  size: size * 0.4,
                  color: theme.colorScheme.primary,
                ),
              )
            : Padding(
                padding: EdgeInsets.all(inset),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  // Decode at display resolution, not the 256px source: a rail
                  // of 16 full-size bitmaps is the classic scroll-jank source.
                  cacheWidth:
                      ((size - inset * 2) *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                ),
              ),
      ),
    );
  }
}
