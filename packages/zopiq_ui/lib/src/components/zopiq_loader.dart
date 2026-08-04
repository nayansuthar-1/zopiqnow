import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The one spinner feature code should use.
///
/// Material's ring on Android, and the real iOS spinner —
/// [CupertinoActivityIndicator], the ticking wheel — on iOS and macOS. A
/// loading state is the most-seen animation in the app, and a Material ring on
/// an iPhone is the single clearest tell that a Flutter app is not native.
///
/// Not `CircularProgressIndicator.adaptive`: that constructor feeds the
/// Cupertino spinner from `backgroundColor`, ignoring `color` and `valueColor`
/// entirely. Every colored spinner in this codebase passes `color`, so
/// `.adaptive` would silently turn each one grey on iOS — and painting them via
/// `backgroundColor` instead would draw a track ring behind the Material one on
/// Android. Two platforms, one knob, and no setting of it that is right for
/// both. Hence an explicit switch.
///
/// [size] is the box the spinner is drawn in; leaving it null gives each
/// platform its own natural size (36 for Material, 20 for Cupertino).
/// [strokeWidth] is Material-only — the iOS spinner has no stroke to set.
class ZopiqLoader extends StatelessWidget {
  const ZopiqLoader({this.color, this.size, this.strokeWidth, super.key});

  /// Spinner color. Null takes each platform's default.
  final Color? color;

  /// Side of the square the spinner is centered in. Null leaves it unbounded,
  /// which is what a full-screen `Center(child: ZopiqLoader())` wants.
  final double? size;

  /// Material ring thickness. Ignored on iOS.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final double? side = size;

    final Widget indicator = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => CupertinoActivityIndicator(
        color: color,
        // The Cupertino spinner sizes itself from a radius, so a caller asking
        // for a 20px box gets a 20px wheel rather than the default 20 regardless.
        radius: side == null ? 10 : side / 2,
      ),
      _ => CircularProgressIndicator(
        color: color,
        strokeWidth: strokeWidth ?? 4,
      ),
    };

    return side == null
        ? indicator
        : SizedBox.square(dimension: side, child: Center(child: indicator));
  }
}
