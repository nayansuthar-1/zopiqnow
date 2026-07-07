import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';
import 'package:zopiq_ui/src/tokens/zopiq_durations.dart';
import 'package:zopiq_ui/src/tokens/zopiq_radii.dart';

/// Animated skeleton loader (Rule 2.5 — every list has shimmer loaders).
///
/// Wrap any layout of [ZopiqSkeletonBox]es in a [ZopiqShimmer]; the sweep is
/// applied to all descendants at once via a shader mask (one animation, cheap
/// on mid-range hardware — Rule 1.4).
class ZopiqShimmer extends StatefulWidget {
  const ZopiqShimmer({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<ZopiqShimmer> createState() => _ZopiqShimmerState();
}

class _ZopiqShimmerState extends State<ZopiqShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ZopiqDurations.shimmer,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final ZopiqColors zc = context.zc;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) {
            final double t = _controller.value;
            return LinearGradient(
              begin: Alignment(-1 - 2 * t, 0),
              end: Alignment(1 - 2 * t, 0),
              colors: <Color>[
                zc.shimmerBase,
                zc.shimmerHighlight,
                zc.shimmerBase,
              ],
              stops: const <double>[0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single grey placeholder block for use inside a [ZopiqShimmer].
class ZopiqSkeletonBox extends StatelessWidget {
  const ZopiqSkeletonBox({
    this.width,
    this.height = 16,
    this.borderRadius = ZopiqRadii.rSm,
    super.key,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.zc.shimmerBase,
        borderRadius: borderRadius,
      ),
    );
  }
}
