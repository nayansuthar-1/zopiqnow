import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/components/zopiq_shimmer.dart';
import 'package:zopiq_ui/src/tokens/zopiq_durations.dart';

/// The one way feature code renders a remote image.
///
/// Handles the three states every network image has — loading, loaded, failed —
/// so no call site reinvents them, and so a dead URL degrades into [fallback]
/// instead of a grey box with a broken-image glyph.
///
/// Performance (Rule 1.4): the bitmap is decoded at the size it will be *drawn*,
/// not the size it was served at. A grid of 800px JPEGs decoded full-size is the
/// classic Android jank-and-OOM source; `cacheWidth` fixes it at the cost of one
/// [LayoutBuilder].
///
/// Caching is Flutter's in-memory [ImageCache] only — images survive a scroll,
/// not an app restart. Disk caching needs `cached_network_image`, a dependency
/// we have not taken; see DEVELOPMENT_PLAN.md.
class ZopiqNetworkImage extends StatelessWidget {
  const ZopiqNetworkImage({
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String url;

  /// Drawn when the URL is empty, fails to load, or the device is offline.
  /// Callers pass their own branded placeholder — zopiq_ui does not guess.
  final Widget fallback;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return fallback;

    final double dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Unbounded width means we cannot size the decode; skip the hint rather
        // than pass a nonsense value.
        final int? cacheWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth * dpr).round()
            : null;

        return Image.network(
          url,
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder:
              (BuildContext context, Widget child, ImageChunkEvent? progress) {
                if (progress == null) return child; // Already decoded.
                return const ZopiqShimmer(
                  child: ZopiqSkeletonBox(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
                  ),
                );
              },
          frameBuilder:
              (
                BuildContext context,
                Widget child,
                int? frame,
                bool wasSynchronouslyLoaded,
              ) {
                // Straight from the cache: no fade, or scrolling back up flickers.
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: ZopiqDurations.base,
                  curve: ZopiqCurves.emphasized,
                  child: child,
                );
              },
        );
      },
    );
  }
}
