import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The Home campaign hero — the "stop the thumb" block under the header.
///
/// Visually it continues the header's brand color into a full-bleed gradient
/// panel (Zomato's home layout), so header + search + hero read as one piece.
///
/// The artwork is a **temporary in-app composition** ([_HeroArt]: rotating ray
/// bursts + campaign typography) until brand art is supplied. When the real
/// image arrives, replace [_HeroArt]'s child with the image — nothing outside
/// that widget knows how the hero is drawn.
///
/// Motion budget (DEVELOPMENT_PLAN — Motion & performance standard): every
/// animation here is a transform or an opacity on a leaf, behind its own
/// [RepaintBoundary]; nothing animates layout. All loops stop when the OS asks
/// for reduced motion.
class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({this.onTapCta, super.key});

  /// "Order now". Home passes a scroll-to-the-restaurants callback.
  final VoidCallback? onTapCta;

  static const double _height = 232;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      // Continues seamlessly from the app bar above, which is solid `primary`.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[ZopiqPalette.primary, ZopiqPalette.primaryDeep],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(ZopiqRadii.xl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _HeroArt(onTapCta: onTapCta),
    );
  }
}

/// The temporary composition. Swap this widget's build for an `Image` (plus
/// the CTA overlay) when the commissioned hero asset lands.
class _HeroArt extends StatefulWidget {
  const _HeroArt({this.onTapCta});

  final VoidCallback? onTapCta;

  @override
  State<_HeroArt> createState() => _HeroArtState();
}

class _HeroArtState extends State<_HeroArt> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: ZopiqDurations.ambient,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ZopiqDurations.breath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient loops obey the OS reduce-motion setting; the hero is then simply
    // a static banner, which is a complete design in its own right.
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
      _pulse.stop();
    } else {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Ray bursts, Zomato-style, rotating imperceptibly slowly. Painted
        // once; the loop only rotates the layer (RepaintBoundary + transform).
        Positioned(
          right: -90,
          top: -70,
          child: RepaintBoundary(
            child: RotationTransition(
              turns: _spin,
              child: const _RayBurst(radius: 190, alpha: 0.10),
            ),
          ),
        ),
        Positioned(
          left: -60,
          bottom: -110,
          child: RepaintBoundary(
            child: RotationTransition(
              turns: ReverseAnimation(_spin),
              child: const _RayBurst(radius: 130, alpha: 0.07),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.pageGutter,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'ZOPIQNOW LAUNCH WEEK',
                style: t.labelSmall?.copyWith(
                  color: ZopiqPalette.white.withValues(alpha: 0.8),
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              Text(
                'ITEMS AT 50% OFF',
                textAlign: TextAlign.center,
                style: t.displayLarge?.copyWith(
                  color: ZopiqPalette.white,
                  fontSize: 38,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  fontVariations: const <FontVariation>[
                    FontVariation('wght', 800),
                  ],
                  shadows: const <Shadow>[
                    Shadow(color: Color(0x33000000), offset: Offset(0, 2)),
                  ],
                ),
              ),
              const SizedBox(height: ZopiqSpacing.xs),
              Text(
                'Free delivery on your first order',
                style: t.bodyMedium?.copyWith(
                  color: ZopiqPalette.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: ZopiqSpacing.lg),
              _PulsingCta(pulse: _pulse, onTap: widget.onTapCta),
            ],
          ),
        ),
      ],
    );
  }
}

/// White "Order now" pill with a slow scale breath — enough motion to catch
/// the eye at a glance, not enough to be noticed while reading.
class _PulsingCta extends StatelessWidget {
  const _PulsingCta({required this.pulse, this.onTap});

  final Animation<double> pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 1,
          end: 1.05,
        ).chain(CurveTween(curve: ZopiqCurves.standard)).animate(pulse),
        child: ZopiqPressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.xl,
              vertical: ZopiqSpacing.md,
            ),
            decoration: const BoxDecoration(
              color: ZopiqPalette.white,
              borderRadius: ZopiqRadii.rPill,
              boxShadow: <BoxShadow>[
                BoxShadow(color: Color(0x40000000), blurRadius: 12),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Order now',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ZopiqPalette.primaryDeep,
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.xs),
                const Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: ZopiqPalette.primaryDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A starburst of triangular rays (the classic promo burst).
class _RayBurst extends StatelessWidget {
  const _RayBurst({required this.radius, required this.alpha});

  final double radius;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(radius * 2),
      painter: _RayBurstPainter(
        color: ZopiqPalette.white.withValues(alpha: alpha),
      ),
    );
  }
}

class _RayBurstPainter extends CustomPainter {
  const _RayBurstPainter({required this.color});

  final Color color;

  static const int _rays = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    final Paint paint = Paint()..color = color;
    final Path path = Path();

    // Each ray is a wedge from the centre; gaps between wedges equal the
    // wedge width, giving the alternating burst.
    const double step = 2 * math.pi / _rays;
    for (int i = 0; i < _rays; i++) {
      final double mid = i * step;
      path
        ..moveTo(c.dx, c.dy)
        ..lineTo(
          c.dx + r * math.cos(mid - step / 4),
          c.dy + r * math.sin(mid - step / 4),
        )
        ..lineTo(
          c.dx + r * math.cos(mid + step / 4),
          c.dy + r * math.sin(mid + step / 4),
        )
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RayBurstPainter oldDelegate) =>
      color != oldDelegate.color;
}
