import 'package:flutter/widgets.dart';

import 'package:zopiq_ui/src/tokens/zopiq_durations.dart';

/// A one-shot entrance: fade up, slightly, once, on first build.
///
/// Used to stage a screen's cards so it *assembles* rather than appearing all at
/// once — the difference between an app that feels built and one that feels
/// rendered. [index] staggers it: card 0 leads, card 1 follows a beat later.
///
/// Constraints this deliberately obeys:
///
/// * **Transform and opacity only.** No layout animates, so a staged screen
///   costs the same as a static one on the Android 10 floor device.
/// * **It settles.** One shot, no loop — a widget test can `pumpAndSettle`
///   through it, which an ambient animation would never allow.
/// * **Reduce-motion removes it entirely**, rather than speeding it up: an
///   entrance the user asked not to see should not be shown quickly.
class ZopiqReveal extends StatelessWidget {
  const ZopiqReveal({
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 40),
    super.key,
  });

  final Widget child;

  /// Position in the sequence. The delay is `index * stagger`, capped so a long
  /// list never leaves its last item waiting a second and a half to exist.
  final int index;

  final Duration stagger;

  /// Beyond this, staggering stops buying anything and starts costing patience.
  static const int _maxStaggered = 6;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final int step = index.clamp(0, _maxStaggered);
    final Duration delay = stagger * step;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: ZopiqDurations.slow + delay,
      curve: Interval(
        // The delay is expressed as a dead zone at the head of the curve rather
        // than a Timer: a Timer would have to be cancelled if the widget went
        // away mid-flight, and a curve cannot leak.
        delay.inMilliseconds / (ZopiqDurations.slow + delay).inMilliseconds,
        1,
        curve: ZopiqCurves.emphasized,
      ),
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
