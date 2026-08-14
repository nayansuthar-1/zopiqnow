import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The round control in the map's bottom-right corner (0125).
///
/// The map and the ad are two faces of one slot: whichever is showing fills the
/// slot, and the other shrinks to this. So there is one widget and not two —
/// "Explore" over the advertiser's logo when the map is up, "Map" over a route
/// glyph when the ad is. Building them separately is how the two ends of a
/// toggle drift a pixel apart and start looking like different controls.
///
/// **Sized to the thumb, not to the art.** 56 across, which is the smallest
/// circle that still clears the 48dp tap target once the label is under it.
class CornerPuck extends StatelessWidget {
  const CornerPuck({
    required this.label,
    required this.onTap,
    this.imageUrl,
    this.icon,
    super.key,
  }) : assert(
         imageUrl != null || icon != null,
         'A puck shows a logo or a glyph — with neither it is a blank circle.',
       );

  /// The word under the circle: "EXPLORE" or "MAP".
  final String label;

  /// The advertiser's mark. Null on the map puck, which draws [icon] instead.
  final String? imageUrl;

  final IconData? icon;

  final VoidCallback onTap;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                // A white circle on a pale map is invisible without this. The
                // shadow is doing the work a border would do badly at this size.
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl != null
                  ? ZopiqNetworkImage(
                      url: imageUrl!,
                      // The advertiser's logo is a composed mark. Cover crops it
                      // to a circle, which is what every brand ships a square
                      // avatar for.
                      fallback: Icon(Icons.storefront_rounded, color: zc.primary),
                    )
                  : Icon(icon, color: zc.primary, size: 26),
            ),
            const SizedBox(height: ZopiqSpacing.xxs),
            // The label rides on its own chip rather than bare on the map: over
            // a satellite tile or a dark road, plain text disappears.
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: ZopiqRadii.rXs,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.xs,
                  vertical: 1,
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: zc.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
