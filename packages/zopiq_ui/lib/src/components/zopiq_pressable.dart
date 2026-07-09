import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/tokens/zopiq_durations.dart';

/// Tap target that compresses slightly while held (Rule 2.6 — micro-interaction).
///
/// Used instead of an ink ripple on image-led surfaces (category tiles, offer
/// cards, restaurant cards), where a ripple would land on top of artwork.
///
/// Only a [Transform.scale] is animated, so the press repaints nothing — it is a
/// pure compositor transform and stays smooth on low-end hardware (Rule 1.4).
class ZopiqPressable extends StatefulWidget {
  const ZopiqPressable({
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Scale applied while the pointer is down. 1.0 disables the effect.
  final double pressedScale;

  @override
  State<ZopiqPressable> createState() => _ZopiqPressableState();
}

class _ZopiqPressableState extends State<ZopiqPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: ZopiqDurations.instant,
        curve: ZopiqCurves.emphasized,
        child: widget.child,
      ),
    );
  }
}
