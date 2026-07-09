import 'package:flutter/material.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// Circular artwork for one dish category.
///
/// This is the **only** place that knows how a category is drawn. The tinted
/// disc is always ours; the foreground is either [FoodCategory.imageAsset] or,
/// when none is set, a stand-in glyph.
///
/// The bundled art is OpenMoji (CC BY-SA 4.0) — free to ship, and a real
/// illustration rather than a placeholder. It is *not* Swiggy's artwork, which
/// is copyrighted. Swapping in commissioned illustrations means dropping new
/// files in `assets/categories/` and changing nothing else.
class CategoryArt extends StatelessWidget {
  const CategoryArt({required this.category, required this.size, super.key});

  final FoodCategory category;
  final double size;

  /// Inset of the artwork inside the disc, as a fraction of [size]. Emoji-style
  /// art is drawn edge to edge, so it needs breathing room the disc provides.
  static const double _insetFactor = 0.18;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? asset = category.imageAsset;
    final double inset = size * _insetFactor;

    // Real artwork brings its own colour, so the disc stays neutral and lets it
    // read. The per-category hue exists only to tell blank placeholders apart.
    if (asset != null) {
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              // Decode at display resolution, not the 618px source: a rail of
              // 16 full-size bitmaps is the classic scroll-jank source.
              cacheWidth:
                  ((size - inset * 2) * MediaQuery.devicePixelRatioOf(context))
                      .round(),
            ),
          ),
        ),
      );
    }

    final bool isDark = theme.brightness == Brightness.dark;
    final double hue = (category.id.hashCode % 360).abs().toDouble();
    final Color base =
        HSLColor.fromAHSL(1, hue, 0.45, isDark ? 0.32 : 0.86).toColor();
    final Color accent =
        HSLColor.fromAHSL(1, hue, 0.55, isDark ? 0.78 : 0.34).toColor();

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[base, Color.lerp(base, accent, 0.18)!],
          ),
        ),
        child: Center(
          child: Icon(
            _fallbackGlyphs[category.id] ?? Icons.restaurant_rounded,
            size: size * 0.44,
            color: accent,
          ),
        ),
      ),
    );
  }

  /// Used only when a category has no bundled art yet.
  static const Map<String, IconData> _fallbackGlyphs = <String, IconData>{
    'biryani': Icons.rice_bowl_rounded,
    'pizza': Icons.local_pizza_rounded,
    'burger': Icons.lunch_dining_rounded,
    'rolls': Icons.kebab_dining_rounded,
    'north_indian': Icons.dinner_dining_rounded,
    'chinese': Icons.ramen_dining_rounded,
    'dosa': Icons.flatware_rounded,
    'idli': Icons.breakfast_dining_rounded,
    'momos': Icons.set_meal_rounded,
    'cake': Icons.cake_rounded,
    'ice_cream': Icons.icecream_rounded,
    'noodles': Icons.ramen_dining_rounded,
    'shawarma': Icons.kebab_dining_rounded,
    'paratha': Icons.bakery_dining_rounded,
    'chaat': Icons.tapas_rounded,
    'pure_veg': Icons.eco_rounded,
  };
}
