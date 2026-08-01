import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The customer's photo, or the letter that stands in for one.
///
/// One widget so the account header and the profile editor cannot disagree
/// about what "no photo" looks like — and so a Cloudinary URL that 404s degrades
/// to the same initial rather than to a broken-image glyph. [ZopiqNetworkImage]
/// already owns the empty / loading / failed cases; this adds the circle, the
/// size, and the fallback worth drawing.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.url,
    required this.initial,
    required this.radius,
    super.key,
  });

  /// Null or empty when they have never set one and no provider supplied one.
  final String? url;

  /// The single character drawn when there is no photo.
  final String initial;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final double diameter = radius * 2;

    final Widget fallback = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: zc.primary.withValues(alpha: 0.12),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: zc.primary,
            // Scales with the circle rather than being set per call site: the
            // same widget is drawn at 28 in the header and 54 in the editor.
            fontSize: radius * 0.8,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );

    return SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: ZopiqNetworkImage(url: url ?? '', fallback: fallback),
      ),
    );
  }
}
