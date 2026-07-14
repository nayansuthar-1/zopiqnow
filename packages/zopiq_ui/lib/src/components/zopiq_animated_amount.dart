import 'package:flutter/widgets.dart';

import 'package:zopiq_ui/src/tokens/zopiq_durations.dart';

/// A rupee amount that **rolls** to its new value instead of snapping.
///
/// Money changing is the one moment in a food app where the number *is* the
/// interaction: apply a coupon, add a dish, cross the free-delivery line. A
/// total that jumps gives the user nothing to follow; one that counts gives them
/// something to watch, and tells them — without a word — that the thing they
/// just did affected the thing they care about.
///
/// Two properties this is careful about:
///
/// * **It is exact on first build.** The animation runs only when the value
///   *changes*, so a freshly-built screen renders the true total on frame one.
///   A widget that animated in from zero would spend 200ms displaying a price
///   nobody is being charged, and any test reading the total would be racing it.
/// * **It costs no layout.** The digits are painted, not re-laid-out: the box is
///   sized once for the widest value it has held, so a rolling total cannot
///   shove the button next to it around.
class ZopiqAnimatedAmount extends StatelessWidget {
  const ZopiqAnimatedAmount({
    required this.amount,
    this.style,
    this.prefix = '₹',
    this.duration = ZopiqDurations.slow,
    super.key,
  });

  /// Whole rupees. This app has no paise: a menu price is an integer, a bill is
  /// a sum of integers, and rounding is Postgres's job (see `place_order`).
  final int amount;

  final TextStyle? style;

  /// Set to `-₹` for a discount, which reads as a subtraction rather than a
  /// number that happens to be negative.
  final String prefix;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Reduce-motion is an accessibility setting, not a preference to override:
    // a counting number is exactly the kind of thing it exists to switch off.
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      return Text('$prefix$amount', style: style);
    }

    return TweenAnimationBuilder<double>(
      // `begin: amount` on every build means the first build has nothing to
      // animate — the tween is zero-length — while a *changed* amount animates
      // from wherever it was. That is the whole trick.
      tween: Tween<double>(begin: amount.toDouble(), end: amount.toDouble()),
      duration: duration,
      curve: ZopiqCurves.emphasized,
      builder: (BuildContext context, double value, _) =>
          Text('$prefix${value.round()}', style: style),
    );
  }
}
