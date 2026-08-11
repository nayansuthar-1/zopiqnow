import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/splash_gate_provider.dart';

/// The first thing a customer sees.
///
/// It still covers the window the router needs it to cover — the session being
/// read out of the Keystore (SAD 24.1), during which redirecting would throw a
/// signed-in user's deep link away. What changed is that it no longer *only*
/// covers it: [splashGateProvider] holds the route open for the length of the
/// animation, because a brand moment that lasts two frames is not one.
///
/// This screen owns *when* that ends. It closes the gate from the completion of
/// its own controller rather than leaving a timer elsewhere to guess the same
/// duration, because the two clocks start at different moments — the gate's
/// began when the router was built, several hundred milliseconds before this
/// widget mounted, and the tagline was being cut off two thirds of the way in.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

/// The tagline, already split. Kept at the top rather than split at render so
/// the per-word intervals below index against something that cannot change
/// underneath them.
const List<String> _tagline = <String>['Food', 'at', 'your', 'doorstep'];

/// How far below the centre the wordmark starts, and therefore how far it
/// travels on its way up to it. Far enough to read as movement, not so far that
/// it arrives from off-screen — it begins a little under the middle and settles
/// into it.
const double _wordmarkRise = 44;

/// The opacity the wordmark starts at, rather than zero — it is already half
/// there when the screen appears, and fades the rest of the way in over the
/// same stretch it spends rising.
const double _wordmarkFloor = 0.5;

/// How far each tagline word comes in from, to the right of where it lands.
const double _wordSlide = 24;

/// The wordmark owns the first stretch of the timeline; the tagline begins at
/// exactly the moment it ends.
///
/// "When ZopiQ reaches the centre, then the tagline" is a sequencing rule, and
/// it is expressed here as a shared boundary on one controller rather than as a
/// second controller started from the first one's completion listener. Two
/// controllers can drift, can both be disposed mid-flight, and give the gap a
/// dropped frame to open up in. One timeline cannot.
const double _wordmarkEnd = 0.44;

/// Where each word starts relative to the one before it, and how long each
/// takes. The last word therefore lands at 0.605 + 0.22 = 0.825, leaving the
/// tail of the hold as a beat to read it on before the app moves.
const double _wordStagger = 0.055;
const double _wordSpan = 0.22;

/// How far below the wordmark the tagline sits.
const double _taglineDrop = 52;

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ref.read(splashHoldProvider),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().then((_) {
      if (!mounted) return;
      // Out of the animation tick and into its own frame. Opening the gate makes
      // the router redirect, and a redirect raised from inside the ticker runs
      // while the tree is mid-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(splashGateProvider.notifier).open();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme text = Theme.of(context).textTheme;
    final Color ink = Theme.of(context).colorScheme.onPrimary;

    // Motion is decoration here, never the message. Someone who has asked the
    // system to stop animating things still gets the words — immediately, and
    // all at once.
    final bool still = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      // The icon's own background colour, so the system splash this takes over
      // from and the screen it hands to are one continuous surface rather than
      // two oranges that nearly match.
      backgroundColor: zc.primaryDeep,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          final double t = still ? 1 : _controller.value;

          // Two Centers stacked, not a Column. A Column would centre the *pair*,
          // which puts the wordmark above the middle of the screen and leaves
          // its 25px rise landing somewhere that is not the centre at all. The
          // wordmark is centred; the tagline hangs off that centre.
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(child: _wordmark(t, text, ink)),
              Center(
                child: Transform.translate(
                  offset: const Offset(0, _taglineDrop),
                  child: _taglineRow(t, text, ink),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ZopiQ, fading in as it rises the last [_wordmarkRise] to the centre.
  Widget _wordmark(double t, TextTheme text, Color ink) {
    final double p = ZopiqCurves.emphasized.transform(
      (t / _wordmarkEnd).clamp(0.0, 1.0),
    );

    return Opacity(
      // From [_wordmarkFloor], not from nothing: the name is legible the instant
      // the screen exists and the fade is the last of the way in, rather than a
      // word that materialises out of an empty orange field.
      opacity: _wordmarkFloor + ((1 - _wordmarkFloor) * p),
      child: Transform.translate(
        // Ends at zero, which is the centre the Center already put it at — so
        // the rise is expressed as a distance still to travel rather than as a
        // layout offset somebody later has to remember to cancel out.
        offset: Offset(0, _wordmarkRise * (1 - p)),
        child: Text(
          'ZopiQ',
          style: text.displayLarge?.copyWith(
            fontSize: 46,
            color: ink,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }

  /// The tagline, a word at a time.
  ///
  /// Opacity and a translation, both of which leave layout alone: the row is
  /// laid out at its full width from the first frame, so the words already
  /// standing do not shuffle sideways as the next one arrives.
  Widget _taglineRow(double t, TextTheme text, Color ink) {
    final List<Widget> children = <Widget>[];

    for (int i = 0; i < _tagline.length; i++) {
      if (i > 0) {
        // A real space would be inside a Text that fades with its own word;
        // this keeps the gap constant while the words come in.
        children.add(const SizedBox(width: 5));
      }

      final double begin = _wordmarkEnd + (i * _wordStagger);
      final double p = ZopiqCurves.emphasized.transform(
        ((t - begin) / _wordSpan).clamp(0.0, 1.0),
      );

      children.add(
        Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(_wordSlide * (1 - p), 0),
            child: Text(
              _tagline[i],
              style: text.titleMedium?.copyWith(color: ink),
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
