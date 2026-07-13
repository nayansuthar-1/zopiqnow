import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';
import 'package:zopiq_ui/src/tokens/zopiq_radii.dart';
import 'package:zopiq_ui/src/tokens/zopiq_spacing.dart';

/// Standard surface container — token radius, soft brand shadow, optional tap
/// ripple. Replaces stock [Card] so every surface reads the same (Rule 2.4).
class ZopiqCard extends StatelessWidget {
  const ZopiqCard({
    required this.child,
    this.padding = ZopiqSpacing.cardPadding,
    this.onTap,
    this.borderRadius = ZopiqRadii.rLg,
    this.elevated = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  /// When false, renders flat (hairline border instead of a shadow).
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surface = Theme.of(context).colorScheme.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: borderRadius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
