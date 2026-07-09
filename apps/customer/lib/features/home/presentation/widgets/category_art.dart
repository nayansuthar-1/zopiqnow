import 'package:flutter/material.dart';

import 'package:zopiqnow/features/home/domain/entities/food_category.dart';

/// Circular artwork for one dish category.
///
/// This is the **only** place that knows how a category is drawn. When licensed
/// illustrations arrive, set [FoodCategory.imageAsset] and every call site picks
/// them up — no layout, sizing, or motion changes.
///
/// Until then it renders generated placeholder art: a tinted disc (hue derived
/// from the id, so a category always looks the same) behind a glyph.
class CategoryArt extends StatelessWidget {
  const CategoryArt({required this.category, required this.size, super.key});

  final FoodCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? asset = category.imageAsset;

    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: asset == null
            ? _PlaceholderArt(category: category, size: size)
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                // Decode at display resolution, not source resolution: a rail of
                // 16 full-size bitmaps is the classic scroll-jank source.
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              ),
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  const _PlaceholderArt({required this.category, required this.size});

  final FoodCategory category;
  final double size;

  /// Glyphs standing in for the illustrations. Deliberately approximate — they
  /// exist to make the rail legible during development, not to ship.
  static const Map<String, IconData> _glyphs = <String, IconData>{
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double hue = (category.id.hashCode % 360).abs().toDouble();
    final Color base = HSLColor.fromAHSL(1, hue, 0.45, isDark ? 0.32 : 0.86).toColor();
    final Color glyph = HSLColor.fromAHSL(1, hue, 0.55, isDark ? 0.78 : 0.34).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[base, Color.lerp(base, glyph, 0.18)!],
        ),
      ),
      child: Center(
        child: Icon(
          _glyphs[category.id] ?? Icons.restaurant_rounded,
          size: size * 0.44,
          color: glyph,
        ),
      ),
    );
  }
}
