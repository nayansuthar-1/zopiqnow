import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The Home hero — a swipeable carousel of campaign slides under the header.
///
/// It continues the header's brand colour into a full-bleed panel (Zomato's
/// home), and now holds several offers the user can swipe between, with page
/// dots and a gentle auto-advance. Each slide's text animates: it lifts and
/// fades in on first build (entrance) and drifts with a parallax as you swipe.
///
/// The slide artwork is a **temporary in-app composition** (gradient + rotating
/// ray bursts + a light sheen) until brand art is supplied. Swap a slide's body
/// for an `Image` when the real asset lands — nothing outside this file changes.
///
/// Motion budget (DEVELOPMENT_PLAN — Motion & performance standard): every loop
/// is a transform or a one-shot opacity behind a [RepaintBoundary]; nothing
/// animates layout. All loops and the auto-advance stop under OS reduce-motion.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    required this.headerInset,
    required this.promoHeight,
    this.onTapCta,
    super.key,
  });

  /// Blank space reserved at the top of every slide so the location + search
  /// header (which the app bar floats over the carousel) never sits on the
  /// promo copy. The gradient still fills behind it, so the header reads as
  /// floating on the hero.
  final double headerInset;

  /// Height of the visible promo area *below* [headerInset] — where the
  /// headline and CTA live. Total carousel height is the sum of the two.
  final double promoHeight;

  /// "Order now". Home passes a scroll-to-the-restaurants callback.
  final VoidCallback? onTapCta;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  final PageController _page = PageController();
  Timer? _auto;
  int _index = 0;
  DateTime _lastInteract = DateTime.fromMillisecondsSinceEpoch(0);
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Auto-advance is a nicety, not the way to see slides — off when the OS
    // asks for reduced motion. Swiping still works.
    if (_reduceMotion) {
      _auto?.cancel();
    } else {
      _startAuto();
    }
  }

  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients) return;
      // Yield to the user: don't yank the page while they're browsing slides.
      if (DateTime.now().difference(_lastInteract) < const Duration(seconds: 6)) {
        return;
      }
      _page.animateToPage(
        (_index + 1) % _slides.length,
        duration: ZopiqDurations.slow,
        curve: ZopiqCurves.emphasized,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = widget.headerInset + widget.promoHeight;
        final double headlineSize = (width * 0.108).clamp(30.0, 44.0);

        return SizedBox(
          height: height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n is UserScrollNotification) _lastInteract = DateTime.now();
              return false;
            },
            child: Stack(
              children: <Widget>[
                PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
                  onPageChanged: (int i) => setState(() => _index = i),
                  itemBuilder: (BuildContext context, int i) => _HeroSlideView(
                    slide: _slides[i],
                    index: i,
                    page: _page,
                    headlineSize: headlineSize,
                    topInset: widget.headerInset,
                    reduceMotion: _reduceMotion,
                    onTapCta: widget.onTapCta,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: ZopiqSpacing.md,
                  child: _Dots(count: _slides.length, active: _index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The page-position indicator. The active dot stretches into a pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool on = i == active;
        return AnimatedContainer(
          duration: ZopiqDurations.base,
          curve: ZopiqCurves.standard,
          width: on ? 22 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: ZopiqPalette.white.withValues(alpha: on ? 1 : 0.5),
            borderRadius: ZopiqRadii.rPill,
          ),
        );
      }),
    );
  }
}

/// One campaign slide: gradient body, ambient decoration, and the animated copy.
class _HeroSlideView extends StatefulWidget {
  const _HeroSlideView({
    required this.slide,
    required this.index,
    required this.page,
    required this.headlineSize,
    required this.topInset,
    required this.reduceMotion,
    this.onTapCta,
  });

  final _HeroSlide slide;
  final int index;
  final PageController page;
  final double headlineSize;
  final double topInset;
  final bool reduceMotion;
  final VoidCallback? onTapCta;

  @override
  State<_HeroSlideView> createState() => _HeroSlideViewState();
}

class _HeroSlideViewState extends State<_HeroSlideView>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: ZopiqDurations.ambient,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ZopiqDurations.breath,
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: ZopiqDurations.slow,
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _entrance.value = 1;
    } else {
      _spin.repeat();
      _sheen.repeat();
      _pulse.repeat(reverse: true);
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _sheen.dispose();
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final _HeroSlide s = widget.slide;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: s.gradient,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(ZopiqRadii.xl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
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
          const Positioned.fill(child: _CenterGlow()),
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _Sheen(animation: _sheen, width: 400, height: 300),
              ),
            ),
          ),
          // The copy: entrance (fade + lift, once) wrapped around a parallax
          // drift driven by the page position, so text slides as you swipe.
          FadeTransition(
            opacity: CurvedAnimation(parent: _entrance, curve: ZopiqCurves.enter),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.14),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _entrance, curve: ZopiqCurves.emphasized),
              ),
              child: AnimatedBuilder(
                animation: widget.page,
                builder: (BuildContext context, Widget? child) {
                  final double page =
                      widget.page.hasClients &&
                          widget.page.position.haveDimensions
                      ? (widget.page.page ?? widget.index.toDouble())
                      : widget.index.toDouble();
                  final double delta = page - widget.index;
                  return Transform.translate(
                    offset: Offset(delta * -30, 0),
                    child: child,
                  );
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    ZopiqSpacing.pageGutter,
                    widget.topInset,
                    ZopiqSpacing.pageGutter,
                    ZopiqSpacing.lg,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _EyebrowPill(icon: s.eyebrowIcon, label: s.eyebrow),
                      const SizedBox(height: ZopiqSpacing.sm),
                      Text(
                        s.headline,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.displayLarge?.copyWith(
                          color: ZopiqPalette.white,
                          fontSize: widget.headlineSize,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          fontVariations: const <FontVariation>[
                            FontVariation('wght', 800),
                          ],
                          shadows: const <Shadow>[
                            Shadow(
                              color: Color(0x33000000),
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.xs),
                      Text(
                        s.subline,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(
                          color: ZopiqPalette.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.md),
                      _PulsingCta(pulse: _pulse, onTap: widget.onTapCta),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A translucent badge for the slide's kicker line.
class _EyebrowPill extends StatelessWidget {
  const _EyebrowPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: ZopiqPalette.white.withValues(alpha: 0.18),
        borderRadius: ZopiqRadii.rPill,
        border: Border.all(color: ZopiqPalette.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: ZopiqPalette.white),
          const SizedBox(width: ZopiqSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ZopiqPalette.white,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterGlow extends StatelessWidget {
  const _CenterGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 0.95,
          colors: <Color>[Color(0x24FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}

/// A diagonal light band sweeping across the panel, then resting off-screen.
class _Sheen extends StatelessWidget {
  const _Sheen({
    required this.animation,
    required this.width,
    required this.height,
  });

  final Animation<double> animation;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double bandWidth = width * 0.22;
    final double bandHeight = height * 1.6;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double p = const Interval(
          0.0,
          0.5,
          curve: Curves.easeInOut,
        ).transform(animation.value);
        final double dx = -bandWidth + (width + bandWidth) * p;
        return Transform.translate(
          offset: Offset(dx, -(bandHeight - height) / 2),
          child: child,
        );
      },
      child: Transform.rotate(
        angle: 0.35,
        child: SizedBox(
          width: bandWidth,
          height: bandHeight,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0x00FFFFFF),
                  Color(0x22FFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White CTA pill with a slow scale breath.
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

/// A starburst of triangular rays.
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

/// One hero slide's content + colours.
@immutable
class _HeroSlide {
  const _HeroSlide({
    required this.eyebrow,
    required this.eyebrowIcon,
    required this.headline,
    required this.subline,
    required this.gradient,
  });

  final String eyebrow;
  final IconData eyebrowIcon;
  final String headline;
  final String subline;
  final List<Color> gradient;
}

/// Placeholder campaign slides. The first stays on the brand orange; the rest
/// use temporary promo gradients (swap for real banner art later, per the
/// class doc). These carry the offers that used to live in the removed cards,
/// plus a teaser for the upcoming Dining feature.
const List<_HeroSlide> _slides = <_HeroSlide>[
  _HeroSlide(
    eyebrow: 'LAUNCH WEEK',
    eyebrowIcon: Icons.bolt_rounded,
    headline: 'ITEMS AT 50% OFF',
    subline: 'Free delivery on your first order',
    gradient: <Color>[ZopiqPalette.primary, ZopiqPalette.primaryDeep],
  ),
  _HeroSlide(
    eyebrow: 'USE TRYNEW',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: '60% OFF',
    subline: 'Up to ₹120 on your first order',
    gradient: <Color>[Color(0xFFFF4E8B), Color(0xFFC31432)],
  ),
  _HeroSlide(
    eyebrow: 'USE ZOPIQ150',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: 'FLAT ₹150 OFF',
    subline: 'On orders above ₹399',
    gradient: <Color>[Color(0xFF7C4DFF), Color(0xFF5B2A9D)],
  ),
  _HeroSlide(
    eyebrow: 'NEW · DINING',
    eyebrowIcon: Icons.restaurant_rounded,
    headline: 'BOOK A TABLE',
    subline: 'Reserve at top spots near you',
    gradient: <Color>[Color(0xFF00B894), Color(0xFF007E63)],
  ),
  _HeroSlide(
    eyebrow: 'USE SAVE30',
    eyebrowIcon: Icons.local_offer_rounded,
    headline: '30% OFF',
    subline: 'Up to ₹75, all weekend',
    gradient: <Color>[Color(0xFF2E86FF), Color(0xFF1C4FD8)],
  ),
];
